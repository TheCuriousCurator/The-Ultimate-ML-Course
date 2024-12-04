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
from utils import HPDI, precis, conditional_independencies, conditional_independencies_v2, find_adjustment_sets, marginal_independencies
#seed = 43
#np.random.seed(seed)
#pyro.set_rng_seed(seed)
torch.multiprocessing.set_sharing_strategy('file_system')

class LegSim:
    def __init__(self, df):
        self.height = tt(df["height"].values).double()
        self.left = tt(df["leg_left"].values).double()
        self.right = tt(df["leg_right"].values).double()
        
    def __call__(self):
        a = pyro.sample("a", Normal(*tt((10., 100.))))
        bl = pyro.sample("bl", Normal(*tt((2., 10.))))
        br = pyro.sample("br", Normal(*tt((2., 10.))))
        sigma = pyro.sample("sigma", Exponential(tt(1.)))
        mu = pyro.deterministic("mu", a + bl*self.left + br*self.right)
        with pyro.plate("N", len(self.height)):
            pyro.sample("height", Normal(mu, sigma), obs=self.height)
        
    def train(self, guide, num_steps):
        pyro.clear_param_store()
        # Initializing to the mean actually causes the multicollinearity to go away...
        #self.guide = AutoMultivariateNormal(self, init_loc_fn=init_to_mean)
        self.guide = guide(self)
        #self.guide = AutoLaplaceApproximation(self)
        svi = SVI(self, guide=self.guide, optim=Adam({"lr": 0.01}), loss=Trace_ELBO())
        loss = []
        for _ in tqdm.notebook.tnrange(num_steps):
            loss.append(svi.step())
        return loss
def plot_intervals(samples, p):
    for i, (k, s) in enumerate(samples.items()):
        mean = s.mean()
        hpdi = HPDI(s, p)
        plt.scatter([mean], [i], facecolor="none", edgecolor="black")
        plt.plot(hpdi, [i, i], color="C0")
        plt.axhline(i, color="grey", alpha=0.5, linestyle="--")
    plt.yticks(range(len(samples)), samples.keys(), fontsize=15)
    plt.axvline(0, color="black", alpha=0.5, linestyle="--")

if __name__ == "__main__":
    N = 100
    height = Normal(10, 2.0).sample([N])
    leg_prop = Uniform(0.4, 0.5).sample([N])
    leg_left = leg_prop * height + Normal(0, 0.2).sample([N])
    leg_right = leg_prop * height + Normal(0, 0.2).sample([N])

    df = pd.DataFrame({ "height": height.numpy(), \
                        "leg_left": leg_left.numpy(), \
                        "leg_right": leg_right.numpy()
                    })
    df.head() 


    m6_1_mcmc = LegSim(df)
    nuts_kernel = NUTS(m6_1_mcmc)

    mcmc = MCMC(nuts_kernel, num_samples=200, warmup_steps=100, num_chains=25, mp_context='spawn')
    mcmc.run()

    hmc_samples = {k: v.detach().cpu().numpy() for k, v in mcmc.get_samples().items()}
    print(hmc_samples["a"].shape, hmc_samples["bl"].shape, hmc_samples["br"].shape, hmc_samples["sigma"].shape)
    mcmc.summary()
    posterior_samples = mcmc.get_samples()
    posterior_predictive_samples = Predictive(m6_1_mcmc, posterior_samples, return_sites=("a", "bl", "br", "sigma"))()
    posterior_predictive_samples = {
            k: v.detach().numpy()
            for k, v in posterior_predictive_samples.items()
        }
    print(precis(hmc_samples))
    plot_intervals(hmc_samples, 0.89)
    plt.axvline(0, color="black", alpha=0.5, linestyle="--")
    plt.show()