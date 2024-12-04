import concurrent.futures

import numpy as np
import pandas as pd
import scipy.stats as st
import matplotlib.pyplot as plt
import tqdm
import networkx as nx

import torch
tt = torch.tensor
import pyro
from pyro.distributions import Normal, Uniform, Exponential, LogNormal

from pyro.nn import PyroModule
from pyro import poutine

from models import RegressionBase
from utils import sample_posterior, precis, HPDI, plot_intervals, conditional_independencies, marginal_independencies, conditional_independencies_v2

class Fig7_6(RegressionBase):
    def __init__(self, df, n_feat):
        super().__init__(df)
        self.n_feat = n_feat
        self.X = torch.stack([getattr(self, f"x{i}") for i in range(n_feat)])
    
    def __call__(self, X=None):
        beta = pyro.sample("beta", Normal(0., 1.0).expand([self.n_feat]).to_event(1)).double()
        if X is None:
            mu = torch.matmul(beta, self.X)
            with pyro.plate("N"):
                pyro.sample("y", Normal(mu, 1.0), obs=self.y)
        else:
            mu = torch.matmul(X, beta)
            pyro.sample("y", Normal(mu, 1.0))
            
def gen_data(n_feat, N):
    X = np.random.randn(N, max(n_feat, 2))
    mu = 0.15*X[:,0] - 0.4*X[:,1]
    y = np.random.randn(N) + mu
    return X[:,:n_feat], y

def LPPD(model, x, y, out_var_nm, num_samples=100):
    logp = torch.zeros((num_samples, len(x)))
    for i in range(num_samples):
        tr = poutine.trace(poutine.condition(model, data=model.guide())).get_trace(x)
        logp[i] = tr.nodes[out_var_nm]["fn"].log_prob(y).detach()
    logpmax = logp.max(axis=0).values # logp = log probabilities of each observation
    # we are using mean instead of sum in log-sum-exp trick because of the LPPD formula.
    lppd = logpmax + (logp - logpmax).exp().mean(axis=0).log() # numerically stable version
    return lppd

def train_test(i):
    # Generate training data
    X, y = gen_data(n_feat, N)
    X = np.concatenate([X, y[:,None]], axis=1)
    d = pd.DataFrame(X, columns=[f"x{i}" for i in range(n_feat)] + ["y"])
    # Train model
    model = Fig7_6(d, n_feat=n_feat)
    loss = model.train(2000, autoguide="AutoDiagonalNormal", use_tqdm=False)
    # Get in-sample deviance
    lppd_train = LPPD(model, model.X.T, tt(y), "y", 100).sum().item()
    # Get out-of-sample deviance
    X, y = gen_data(n_feat, N)
    lppd_test = LPPD(model, tt(X), tt(y), "y", 100).sum().item()
    return -2*lppd_train, -2*lppd_test


deviance = {
    n: {
        "in": {i: [] for i in range(1, 6)},
        "out": {i: [] for i in range(1, 6)},
    } for n in (20, 100)
}
num_simulations = 10000
pbar = tqdm.trange(2*5*num_simulations)
for N in (20, 100):
    # Loop over number of features to use
    for n_feat in range(1, 6):
        # Loop over simulations
        # doing it in parallel
        with concurrent.futures.ProcessPoolExecutor(max_workers=18) as pool:
            deviance_train, deviance_test = zip(*pool.map(train_test, range(num_simulations)))
            deviance[N]["in"][n_feat].extend(deviance_train)
            deviance[N]["out"][n_feat].extend(deviance_test)
        pbar.update(num_simulations)
pbar.close()

fig, axes = plt.subplots(ncols=2, figsize=(12, 6))

for (N, d1), ax in zip(deviance.items(), axes):
    plt.sca(ax)
    plt.xlabel("number of parameters")
    plt.ylabel("deviance")
    plt.title(f"N = {N}")
    for in_out, d2 in d1.items():
        options = dict(
            color = "C0" if (in_out == "in") else "black",
            edgecolor = "C0" if (in_out == "in") else "black",
            facecolor = "C0" if (in_out == "in") else "none",
        )
        offset = 0 if (in_out == "in") else 0.25
        for n_feat, sample in d2.items():
            mean = np.mean(sample)
            std = np.std(sample)
            plt.scatter([n_feat+offset], [mean], **options)
            x = 2*[n_feat + offset]
            y = [mean + std, mean - std]
            plt.plot(x, y, color=options["color"])
    plt.legend()
plt.plot([], [], color="C0", label="in")
plt.plot([], [], color="black", label="out")
fig.suptitle("In/out of sample deviance with increasing # of parameters", fontsize=20)
plt.legend()
plt.show()
