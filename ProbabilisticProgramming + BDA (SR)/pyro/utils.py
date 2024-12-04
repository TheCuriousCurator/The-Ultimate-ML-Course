import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import networkx as nx
from networkx.algorithms.moral import moral_graph
from networkx.algorithms.dag import ancestors
from networkx.algorithms.shortest_paths import has_path

import inspect
import os
import re
import warnings
import daft
import seaborn as sns
import torch
import pyro
import pyro.distributions as dist
from pyro.infer.mcmc import NUTS, MCMC
from pyro.contrib.autoguide import AutoLaplaceApproximation
from pyro.infer import TracePosterior, TracePredictive, Trace_ELBO, Predictive
from pyro import poutine
import pyro.ops.stats as stats
from pyro.ops.welford import WelfordCovariance

import collections
import itertools

from torch.distributions import constraints
from pyro.distributions import TorchDistribution, Categorical
from pyro.distributions.transforms import Transform
from torch.distributions.utils import lazy_property
### Sample summarization and interval calculation

def HPDI(samples, prob):
    """Calculates the Highest Posterior Density Interval (HPDI)
    
    Sorts all the samples, then with a fixed width window (in index space), 
    iterates through them all and caclulates the interval width, taking the 
    maximimum as it moves along. Probably only useful/correct for continuous 
    distributions or discrete distributions with a notion of ordering and a large 
    number of possible values.
    Arguments:
        samples (np.array): array of samples from a 1-dim posterior distribution
        prob (float): the probability mass of the desired interval
    Returns:
        Tuple[float, float]: the lower/upper bounds of the interval
    """
    samples = sorted(samples)
    N = len(samples)
    W = int(round(N*prob))
    min_interval = float('inf')
    bounds = [0, W]
    for i in range(N-W):
        interval = samples[i+W] - samples[i]
        if interval < min_interval:
            min_interval = interval
            bounds = [i, i+W]
    return samples[bounds[0]], samples[bounds[1]]


def precis(samples: dict, prob=0.89):
    """Computes some summary statistics of the given samples.
    
    Arguments:
        samples (Dict[str, np.array]): dictionary of samples, where the key
            is the name of the sample site, and the value is the collection
            of sample values
        prob (float): the probability mass of the symmetric credible interval
    Returns:
        pd.DataFrame: summary dataframe
    """
    p1, p2 = (1-prob)/2, 1-(1-prob)/2
    cols = ["mean","stddev",f"{100*p1:.1f}%",f"{100*p2:.1f}%"]
    df = pd.DataFrame(columns=cols, index=samples.keys())
    if isinstance(samples, pd.DataFrame):
        samples = {k: np.array(samples[k]) for k in samples.columns}
    elif not isinstance(samples, dict):
        raise TypeError("<samples> must be either dict or DataFrame")
    for k, v in samples.items():
        df.loc[k,"mean"] = v.mean()
        df.loc[k,"stddev"] = v.std()
        q1, q2 = np.quantile(v, [p1, p2])
        df.loc[k,f"{100*p1:.1f}%"] = q1
        df.loc[k,f"{100*p2:.1f}%"] = q2
    return df

### Causal inference tools

def independent(G, n1, n2, n3=None):
    """Computes whether n1 and n2 are independent given n3 on the DAG G
    
    Can find a decent exposition of the algorithm at http://web.mit.edu/jmn/www/6.034/d-separation.pdf
    """
    if n3 is None:
        n3 = set()
    elif isinstance(n3, (int, str)):
        n3 = set([n3])
    elif not isinstance(n3, set):
        n3 = set(n3)
    # Construct the ancestral graph of n1, n2, and n3
    a = ancestors(G, n1) | ancestors(G, n2) | {n1, n2} | n3
    G = G.subgraph(a)
    # Moralize the graph
    M = moral_graph(G)
    # Remove n3 (if applicable)
    M.remove_nodes_from(n3)
    # Check that path exists between n1 and n2
    return not has_path(M, n1, n2)

def conditional_independencies(G):
    """Finds all conditional independencies in the DAG G
    
    Only works when conditioning on a single node at a time
    """
    tuples = []
    for i1, n1 in enumerate(G.nodes):
        for i2, n2 in enumerate(G.nodes):
            if i1 >= i2:
                continue
            for n3 in G.nodes:
                try:
                    if independent(G, n1, n2, n3):
                        tuples.append((n1, n2, n3))
                except:
                    pass
    return tuples

def conditional_independencies_v2(G):
    """Finds all conditional independencies in the DAG G
    Works when conditioning on multiple nodes at a time
    """
    d = collections.defaultdict(list)
    conditional_independence = collections.defaultdict(list)
    for edge in itertools.combinations(sorted(G.nodes), 2):
        remaining = sorted(set(G.nodes) - set(edge))
        for size in range(len(remaining) + 1):
            for subset in itertools.combinations(remaining, size):
                if any(cond.issubset(set(subset)) for cond in conditional_independence[edge]):
                    continue
                if nx.d_separated(G, {edge[0]}, {edge[1]}, set(subset)):
                    conditional_independence[edge].append(set(subset))
                    #print(f"{edge[0]} _||_ {edge[1]}" + (f" | {' '.join(subset)}" if subset else ""))
    return collections.defaultdict(list, {k:v for k,v in conditional_independence.items() if len(v)>0})

def find_adjustment_sets(G):
    """
    Returns the all adjustment set in a DAG
    """
    backdoor_paths = [path for path in nx.all_simple_paths(G.to_undirected(), "W", "D")
                  if G.has_edge(path[1], "W")]
    remaining = sorted(set(G.nodes) - {"W", "D"} - set(nx.descendants(G, "W")))
    adjustment_sets = []
    for size in range(len(remaining) + 1):
        for subset in itertools.combinations(remaining, size):
            subset = set(subset)
            if any(s.issubset(subset) for s in adjustment_sets):
                continue
            need_adjust = True
            for path in backdoor_paths:
                d_separated = False
                for x, z, y in zip(path[:-2], path[1:-1], path[2:]):
                    if G.has_edge(x, z) and G.has_edge(y, z):
                        if set(nx.descendants(G, z)) & subset:
                            continue
                        d_separated = z not in subset
                    else:
                        d_separated = z in subset
                    if d_separated:
                        break
                if not d_separated:
                    need_adjust = False
                    break
            if need_adjust:
                adjustment_sets.append(subset)
                #print(subset)
    return adjustment_sets

def marginal_independencies(G):
    """Finds all marginal independencies in the DAG G
    """
    tuples = []
    for i1, n1 in enumerate(G.nodes):
        for i2, n2 in enumerate(G.nodes):
            if i1 >= i2:
                continue
            try:
                if independent(G, n1, n2, {}):
                    tuples.append((n1, n2, {}))
            except:
                pass
    return tuples

def sample_posterior(model, num_samples, sites=None, data=None):
    p = Predictive(
        model,
        guide=model.guide,
        num_samples=num_samples,
        return_sites=sites,
    )
    if data is None:
        p = p()
    else:
        p = p(data)
    return {k: v.detach().numpy() for k, v in p.items()}

def sample_prior(model, num_samples, sites=None):
    return {
        k: v.detach().numpy()
        for k, v in Predictive(
            model,
            {},
            return_sites=sites,
            num_samples=num_samples
        )().items()
    }

def plot_intervals(samples, p, vline=0):
    for i, (k, s) in enumerate(samples.items()):
        mean = s.mean()
        hpdi = HPDI(s, p)
        plt.scatter([mean], [i], facecolor="none", edgecolor="black")
        plt.plot(hpdi, [i, i], color="C0")
        plt.axhline(i, color="grey", alpha=0.5, linestyle="--")
    plt.yticks(range(len(samples)), samples.keys(), fontsize=15)
    plt.axvline(vline, color="black", alpha=0.5, linestyle="--")
    #plt.show()
    
    
def WAIC(model, x, y, out_var_nm, num_samples=100):
    p = torch.zeros((num_samples, len(y)))
    # Get log probability samples
    for i in range(num_samples):
        tr = poutine.trace(poutine.condition(model, data=model.guide())).get_trace(x)
        dist = tr.nodes[out_var_nm]["fn"]
        p[i] = dist.log_prob(y).detach()
    pmax = p.max(axis=0).values
    lppd = pmax + (p - pmax).exp().mean(axis=0).log() # numerically stable version
    penalty = p.var(axis=0)
    return -2*(lppd - penalty)


def format_data(df, categoricals=None):
    data = dict()
    if categoricals is None:
        categoricals = []
    for col in set(df.columns) - set(categoricals):
        data[col] = torch.tensor(df[col].values).double()
    for col in categoricals:
        data[col] = torch.tensor(df[col].values).long()
    return data


def train_nuts(model, data, num_warmup, num_samples, num_chains=1, **kwargs):
    _kwargs = dict(adapt_step_size=True, adapt_mass_matrix=True, jit_compile=True)
    _kwargs.update(kwargs)
    print(_kwargs)
    kernel = NUTS(model, **_kwargs)
    engine = MCMC(kernel, num_samples, num_warmup, num_chains=num_chains)
    engine.run(data, training=True)
    return engine


def traceplot(s, num_chains=1):
    fig, axes = plt.subplots(nrows=len(s), figsize=(12, len(s)*5))
    for (k, v), ax in zip(s.items(), axes):
        plt.sca(ax)
        if num_chains > 1:
            for c in range(num_chains):
                plt.plot(v[c], linewidth=0.5)
        else:
            plt.plot(v, linewidth=0.5)
        plt.ylabel(k)
    plt.xlabel("Sample index")
    return fig

def trankplot(s, num_chains):
    fig, axes = plt.subplots(nrows=len(s), figsize=(12, len(s)*num_chains))
    ranks = {k: np.argsort(v, axis=None).reshape(v.shape) for k, v in s.items()}
    num_samples = 1
    for p in list(s.values())[0].shape:
        num_samples *= p
    bins = np.linspace(0, num_samples, 30)
    for i, (ax, (k, v)) in enumerate(zip(axes, ranks.items())):
        for c in range(num_chains):
            ax.hist(v[c], bins=bins, histtype="step", linewidth=2, alpha=0.5)
        ax.set_xlim(left=0, right=num_samples)
        ax.set_yticks([])
        ax.set_ylabel(k)
    plt.xlabel("sample rank")
    return fig


def unnest_samples2(s, max_depth=1):
    """Unnests samples from multivariate distributions
    
    The general index structure of a sample tensor is
    [[chains,] samples [,idx1, idx2, ...]]. Sometimes the distribution is univariate
    and there are no additional indices. So we will always unnest from the right, but
    only if the tensor has rank of 3 or more (2 in the case of no grouping by chains).
    """
    def _unnest_samples(s):
        _s = dict()
        for k in s:
            assert s[k].dim() > 0
            if s[k].dim() == 1:
                _s[k] = s[k]
            elif s[k].dim() == 2:
                for i in range(s[k].shape[1]):
                    _s[f"{k}[{i}]"] = s[k][:,i]
            else:
                for i in range(s[k].shape[1]):
                    _s[f"{k}[{i}]"] = s[k][:,i,...]
        return _s
    
    for _ in range(max_depth):
        s = _unnest_samples(s)
        if all([v.dim() == 1 for v in s.values()]):
            break
    return s


def unnest_samples(samples: dict, group_by_chain=False, depth=1):
    """Unnests samples from multivariate distributions
    
    The general index structure of a sample tensor is
    [[chains,] samples [,idx1, idx2, ...]]. Sometimes the distribution is univariate
    and there are no additional indices. So we will always unnest from the right, but
    only if the tensor has rank of 3 or more (2 in the case of no grouping by chains).
    """
    _samples = samples.copy()
    for k, s in samples.items():
        n_idx = len(s.shape) - (group_by_chain + 1)
        if n_idx > 0:
            for i in range(s.shape[-n_idx]):
                _samples[f"{k}[{i}]"] = s[...,i]
            del _samples[k]
    if depth >= 2:
        _samples = unnest_samples(_samples, group_by_chain, depth-1)
    return _samples


def get_log_prob(mcmc, data, site_names):
    """Gets the pointwise log probability of the posterior density conditioned on the data
    
    Arguments:
        mcmc (pyro.infer.mcmc.MCMC): the fitted MC model
        data (dict): dictionary containing all the input data (including return sites)
        site_names (str or List[str]): names of return sites to measure log likelihood at
    Returns:
        Tensor: pointwise log-likelihood of shape (num posterior samples, num data points)
    """
    samples = mcmc.get_samples()
    model = mcmc.kernel.model
    # get number of samples
    N = [v.shape[0] for v in samples.values()]
    assert [n == N[0] for n in N]
    N = N[0]
    if isinstance(site_names, str):
        site_names = [site_names]
    # iterate over samples
    log_prob = torch.zeros(N, len(data[site_names[0]]))
    for i in range(N):
        # condition on samples and get trace
        s = {k: v[i] for k, v in samples.items()}
        for nm in site_names:
            s[nm] = data[nm]
        tr = poutine.trace(poutine.condition(model, data=s)).get_trace(data)
        # get pointwise log probability
        for nm in site_names:
            node = tr.nodes[nm]
            log_prob[i] += node["fn"].log_prob(node["value"])
    return log_prob

def draw_PGM(G, coordinates, node_unit=1.0):
    pgm = daft.PGM(node_unit=node_unit)    
    for node in G.nodes:
        pgm.add_node(node, node, *coordinates[node])
    for edge in G.edges:
        pgm.add_edge(*edge)
    with plt.rc_context({"figure.constrained_layout.use": False}):
        pgm.render()
    plt.show()


class OrderedCategorical(TorchDistribution):
    """
    # https://github.com/pyro-ppl/pyro/issues/2571
    # https://docs.pyro.ai/en/dev/_modules/pyro/distributions/ordered_logistic.html#OrderedLogistic

    Alternative parametrization of the distribution over a categorical variable.
    
    Instead of the typical parametrization of a categorical variable in terms
    of the probability mass of the individual categories ``p``, this provides an
    alternative that is useful in specifying ordered categorical models. This
    accepts a list of ``cutpoints`` which are a (potentially initially unordered)
    vector of real numbers denoting baseline cumulative log-odds of the individual
    categories, and a model vector ``phi`` which modifies the baselines for each
    sample individually.
    
    These cumulative log-odds are then transformed into a discrete cumulative
    probability distribution, that is finally differenced to return the probability
    mass function ``p`` that specifies the categorical distribution.
    """
    support = constraints.nonnegative_integer
    arg_constraints = {"phi": constraints.real, "cutpoints": constraints.real}
    has_rsample = False
    
    def __init__(self, phi, cutpoints):
        assert len(cutpoints.shape) == 1 # cutpoints must be 1d vector
        assert len(phi.shape) == 1 # model terms must be 1d vector of samples
        N, K = phi.shape[0], cutpoints.shape[0] + 1
        #cutpoints = torch.sort(cutpoints).values.reshape(1, -1)  # sort and reshape for broadcasting
        cutpoints = cutpoints.exp().cumsum(dim=-1).log() # my addition. from pyro forum.
        cutpoints = cutpoints.reshape(1, -1)
        q = torch.sigmoid(cutpoints - phi.reshape(-1, 1))  # cumulative probabilities
        # turn cumulative probabilities into probability mass of categories
        p = torch.zeros((N, K)) # (batch/sample dim, categories)
        p[:,0] = q[:,0]
        p[:,1:-1] = (q - torch.roll(q, 1, dims=1))[:,1:]
        p[:,-1] = 1 - q[:,-1]
        self.cum_prob = q
        self.dist = Categorical(p)
        
    def sample(self, *args, **kwargs):
        return self.dist.sample(*args, **kwargs)
    
    def log_prob(self, *args, **kwargs):
        return self.dist.log_prob(*args, **kwargs)
    
    @property
    def _event_shape(self):
        return self.dist._event_shape
    
    @property
    def _batch_shape(self):
        return self.dist._batch_shape

class OrderedTransform(Transform):
    codomain = constraints.real_vector
    bijective = True

    def __init__(self):
        super().__init__()

    def _call(self, x):
        """
        :param x: the input into the bijection
        :type x: torch.Tensor

        Invokes the bijection x=>y; in the prototypical context of a
        :class:`~pyro.distributions.TransformedDistribution` `x` is a sample from
        the base distribution (or the output of a previous transform)
        """
        z = torch.cat([x[..., :1], torch.exp(x[..., 1:])], dim=-1)
        return torch.cumsum(z, dim=-1)

    def _inverse(self, y):
        """
        :param y: the output of the bijection
        :type y: torch.Tensor

        Inverts y => x.
        """
        x = torch.log(y[..., 1:] - y[..., :-1])
        return torch.cat([y[..., :1], x], dim=-1)

    def log_abs_det_jacobian(self, x, y):
        """
        Calculates the elementwise determinant of the log Jacobian, i.e.
        log(abs([dy_0/dx_0, ..., dy_{N-1}/dx_{N-1}])).
        """

        return torch.sum(x[..., 1:], dim=-1)
    
def plot_errorbar(
    xs, ys, error_lower, error_upper, colors="C0", error_width=12, alpha=0.3
):
    if isinstance(colors, str):
        colors = [colors] * len(xs)

    """Draw thick error bars with consistent style"""
    for ii, (x, y, err_l, err_u) in enumerate(zip(xs, ys, error_lower, error_upper)):
        marker, _, bar = plt.errorbar(
            x=x,
            y=y,
            yerr=np.array((err_l, err_u))[:, None],
            ls="none",
            color=colors[ii],
            zorder=1,
        )
        plt.setp(bar[0], capstyle="round")
        marker.set_fillstyle("none")
        bar[0].set_alpha(alpha)
        bar[0].set_linewidth(error_width)