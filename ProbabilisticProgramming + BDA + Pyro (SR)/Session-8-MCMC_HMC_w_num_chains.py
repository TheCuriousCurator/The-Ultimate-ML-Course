import sys
import time
from collections import deque
import collections
import itertools

import arviz as az
import numpy as np
import scipy.stats as st
import matplotlib.pyplot as plt
import pandas as pd
import tqdm
import networkx as nx

import torch
tt = torch.tensor
import pyro
from pyro.distributions import Normal, Uniform, Exponential, LogNormal
from pyro.infer import SVI, Predictive, Trace_ELBO #, NUTS, MCMC
from pyro.optim import Adam, SGD
from pyro.infer.autoguide import AutoMultivariateNormal, init_to_mean, AutoNormal, AutoLaplaceApproximation

from pyro.infer.mcmc.api import MCMC, NUTS
from pyro.infer.mcmc.nuts import HMC
from models import RegressionBase
from utils import HPDI, precis, sample_posterior, conditional_independencies, conditional_independencies_v2, find_adjustment_sets, marginal_independencies
#seed = 43
#np.random.seed(seed)
#pyro.set_rng_seed(seed)
torch.multiprocessing.set_sharing_strategy('file_system')

class M8_5(RegressionBase):
    def __call__(self, data=None):
        a = pyro.sample("a", Normal(1., 0.1).expand([2]).to_event(1))
        b = pyro.sample("b", Normal(0., 0.3).expand([2]).to_event(1))
        sigma = pyro.sample("sigma", Exponential(1.))
        if data is None:
            A = self.cid
            mu = a[A] + b[A] * (self.rugged_std - 0.215)
            with pyro.plate("N"):
                pyro.sample("log_gdp_std", Normal(mu, sigma), obs=self.log_gdp_std)
        else:
            A = data["cid"]
            mu = a[A] + b[A] * (data["rugged_std"] - 0.215)
            return pyro.sample("log_gdp_std", Normal(mu, sigma))
        
def traceplot(s, num_chains):
    fig, axes = plt.subplots(nrows=len(s), figsize=(12, len(s)*num_chains))
    for (k, v), ax in zip(s.items(), axes):
        plt.sca(ax)
        for c in range(num_chains):
            plt.plot(v[c], linewidth=1)
        plt.ylabel(k)
    plt.xlabel("Sample index")
    return fig

# https://stackoverflow.com/a/50409663
# Define the model; no guide needed
class M9_1:
    def __init__(self, df, categoricals=None):
        if categoricals is None:
            categoricals = []
        for col in set(df.columns) - set(categoricals):
            setattr(self, col, tt(df[col].values).double())
        for col in categoricals:
            setattr(self, col, tt(df[col].values).long())
    
    def model(self, data=None):
        a = pyro.sample("a", Normal(1., 0.1).expand([2]).to_event(1))
        b = pyro.sample("b", Normal(0., 0.3).expand([2]).to_event(1))
        sigma = pyro.sample("sigma", Exponential(1.))
        if data is None:
            A = self.cid
            mu = a[A] + b[A] * (self.rugged_std - 0.215)
            with pyro.plate("N"):
                pyro.sample("log_gdp_std", Normal(mu, sigma), obs=self.log_gdp_std)
        else:
            A = data["cid"]
            mu = a[A] + b[A] * (data["rugged_std"] - 0.215)
            return pyro.sample("log_gdp_std", Normal(mu, sigma))
        
    def train(self, num_warmup, num_samples, num_chains=1, mp_context='spawn'):
        # apparently multiple chains does not work on windows; I should switch over to 
        # my ubuntu partition and try it out later
        kernel = NUTS(self.model, adapt_step_size=True, adapt_mass_matrix=True, jit_compile=True)
        self.engine = MCMC(kernel, num_samples, num_warmup, num_chains=num_chains)
        self.engine.run()

def model_m9_1(data, training=False):
    a = pyro.sample("a", Normal(1., 0.1).expand([2]).to_event(1))
    b = pyro.sample("b", Normal(0., 0.3).expand([2]).to_event(1))
    sigma = pyro.sample("sigma", Exponential(1.))
    A = data["cid"]
    mu = a[A] + b[A] * (data["rugged_std"] - 0.215)
    if training:
        with pyro.plate("N"):
            pyro.sample("log_gdp_std", Normal(mu, sigma), obs=data["log_gdp_std"])
    else:
        return pyro.sample("log_gdp_std", Normal(mu, sigma))

def model_m9_2(data, training=False):
    a = pyro.sample("a", Normal(0., 1000.))
    sigma = pyro.sample("sigma", Exponential(0.0001))
    mu = a
    if training:
        pyro.sample("y", Normal(mu, sigma), obs=data["y"])
    else:
        return pyro.sample("y", Normal(mu, sigma))

def model_m9_3(data, training=False):
    a = pyro.sample("a", Normal(1., 10.))
    sigma = pyro.sample("sigma", Exponential(1.))
    mu = a
    if training:
        with pyro.plate("N"):
            pyro.sample("y", Normal(mu, sigma), obs=data["y"])
    else:
        return pyro.sample("y", Normal(mu, sigma))

def model_m9_4(data, training=False):
    a1 = pyro.sample("a1", Normal(0., 1000.))
    a2 = pyro.sample("a2", Normal(0., 1000.))
    sigma = pyro.sample("sigma", Exponential(1.))
    mu = a1 + a2
    if training:
        pyro.sample("y", Normal(mu, sigma), obs=data["y"])
    else:
        return pyro.sample("y", Normal(mu, sigma))

def model_m9_5(data, training=False):
    a1 = pyro.sample("a1", Normal(0., 10.))
    a2 = pyro.sample("a2", Normal(0., 10.))
    sigma = pyro.sample("sigma", Exponential(1.))
    mu = a1 + a2
    if training:
        pyro.sample("y", Normal(mu, sigma), obs=data["y"])
    else:
        return pyro.sample("y", Normal(mu, sigma))

def model_m9_6(data, training=False):
    # sqrt(2) = 1.41, and var(a1 + a2) = var(a1) + var(a2) for independent normals
    mu = pyro.sample("mu", Normal(0., 14.1))
    sigma = pyro.sample("sigma", Exponential(1.))
    if training:
        pyro.sample("y", Normal(mu, sigma), obs=data["y"])
    else:
        return pyro.sample("y", Normal(mu, sigma))

def format_data(df, categoricals=None):
    data = dict()
    if categoricals is None:
        categoricals = []
    for col in set(df.columns) - set(categoricals):
        data[col] = tt(df[col].values).double()
    for col in categoricals:
        data[col] = tt(df[col].values).long()
    return data

def train_nuts(model, data, num_warmup, num_samples, num_chains=1, mp_context='spawn'):
    kernel = NUTS(model, adapt_step_size=False, adapt_mass_matrix=True, jit_compile=True)
    engine = MCMC(kernel, num_samples, num_warmup, num_chains=num_chains, mp_context=mp_context)
    engine.run(data, training=True)
    return engine


def train_HMC(model, data, num_warmup, num_samples, num_chains=1, step_size=0.1, num_steps=10, mp_context='spawn'):
    kernel = HMC(model, step_size=step_size, num_steps=num_steps) 
    engine = MCMC(kernel, num_samples, num_warmup, num_chains=num_chains, mp_context=mp_context)
    engine.run(data, training=True)
    return engine

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
        # recompute the ax.dataLim
        ax.relim()
        # update ax.viewLim using the new dataLim
        ax.autoscale_view()
        ax.set_yticks([])
        ax.set_ylabel(k)
    plt.xlabel("sample rank")
    return fig

if __name__ == "__main__":
    rugged_df = pd.read_csv("data/rugged.csv", sep=";")
    rugged_df.head()
    d = rugged_df.assign(log_gdp=np.log(rugged_df["rgdppc_2000"]))
    dd = d[~d["log_gdp"].isna()].copy()
    dd["log_gdp_std"] = dd["log_gdp"] / dd["log_gdp"].mean()
    dd["rugged_std"] = dd["rugged"] / dd["rugged"].max()
    dd["cid"] = dd["cont_africa"].astype(int)

    print("Starting M8_5 SVI")
    m8_5 = M8_5(dd[["log_gdp_std", "rugged_std", "cid"]], categoricals=("cid",))
    loss = m8_5.train(1000, use_tqdm=False)
    plt.plot(loss); plt.show()
    samples = {"m8.5": sample_posterior(m8_5, 1000, ("a", "b", "sigma"))}
    s = samples["m8.5"]
    for var in ("a", "b"):
        for i in (0, 1):
            s[f"{var}[{i}]"] = s[var].squeeze()[:,i]
        del s[var]
    print(precis(s))

    print("Starting M9_1 1-chain")
    m9_1 = M9_1(dd[["log_gdp_std", "rugged_std", "cid"]], categoricals=("cid",))
    m9_1.train(1000, 1000, 1)
    
    num_chains = 3
    step_size = 0.15
    num_steps = 3
    print(f"Starting M9_1 {num_chains}-chain")
    data = format_data(dd[["log_gdp_std", "rugged_std", "cid"]], categoricals=("cid",))
    m9_1 = train_HMC(model_m9_1, data, 1000, 1000, num_chains) # I should have 4 cpu's, but pyro only recognizes 3...
    samples["m9.1"] = {k: v.numpy() for k, v in m9_1.get_samples().items()}
    s = samples["m9.1"]
    for var in ("a", "b"):
        for i in (0, 1):
            s[f"{var}[{i}]"] = s[var][:,i]
        del s[var]
    print(precis(s))
    print(m9_1.summary(prob=0.89))
    x = pd.DataFrame(s)
    pd.plotting.scatter_matrix(x, hist_kwds={"bins": 30}, alpha=0.2, figsize=(12, 12))
    plt.show()

    s = {k: v.numpy() for k, v in m9_1.get_samples(group_by_chain=True).items()}
    print(s.keys())
    for var in ("a", "b"):
        for i in (0, 1):
            s[f"{var}[{i}]"] = s[var][:,:,i]
        del s[var]
    print(len(s))
    f = traceplot(s, 3)
    plt.show()
    trankplot(s, 3)
    plt.show()

    print(f"Starting M9_2 {num_chains}-chain")
    num_chains = 3
    step_size = 0.05
    num_steps = 10
    data = {"y": tt([-1., 1.])}
    m9_2 = train_HMC(model_m9_2, data, 1000, 1000, num_chains=num_chains, step_size=step_size, num_steps=num_steps)
    print(m9_2.summary())
    s = {k: v.numpy() for k, v in m9_2.get_samples(group_by_chain=True).items()}
    traceplot(s, num_chains)
    plt.show()
    trankplot(s, num_chains)
    plt.show()

    print(f"Starting M9_3 {num_chains}-chain")
    num_chains = 3
    step_size = 0.15
    num_steps = 3
    data = {"y": tt([-1., 1.])}
    m9_3 = train_HMC(model_m9_3, data, 1000, 1000, num_chains=num_chains, step_size=step_size, num_steps=num_steps)
    print(m9_3.summary())
    traceplot(m9_3.get_samples(group_by_chain=True), num_chains)
    plt.show()
    trankplot(m9_3.get_samples(group_by_chain=True), num_chains)
    plt.show()
    
    print(f"Starting M9_4 {num_chains}-chain")
    num_chains = 3
    step_size = 0.15
    num_steps = 3
    m9_4 = train_HMC(model_m9_4, data, 1000, 1000, num_chains=num_chains, step_size=step_size, num_steps=num_steps)
    print(m9_4.summary())
    traceplot(m9_4.get_samples(group_by_chain=True), num_chains)
    plt.show()
    trankplot(m9_4.get_samples(group_by_chain=True), num_chains)
    plt.show()

    print(f"Starting M9_5 {num_chains}-chain")
    num_chains = 3
    step_size = 0.15
    num_steps = 3
    m9_5 = train_HMC(model_m9_5, data, 1000, 1000, num_chains=num_chains, step_size=step_size, num_steps=num_steps)
    print(m9_5.summary())
    traceplot(m9_5.get_samples(group_by_chain=True), num_chains)
    plt.show()
    trankplot(m9_5.get_samples(group_by_chain=True), num_chains)
    plt.show()
    
    print(f"Starting M9_6 {num_chains}-chain")
    num_chains = 3
    step_size = 0.15
    num_steps = 3
    m9_6 = train_HMC(model_m9_6, data, 1000, 1000, num_chains=num_chains, step_size=step_size, num_steps=num_steps)
    print(m9_6.summary())
    traceplot(m9_6.get_samples(group_by_chain=True), num_chains)
    plt.show()
    trankplot(m9_6.get_samples(group_by_chain=True), num_chains)
    plt.show()
