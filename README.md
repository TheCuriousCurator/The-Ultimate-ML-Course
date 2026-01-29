# The Ultimate ML Course

<p align="center">
  <img src="images/TCC-logos.jpeg" width="200"/>
</p>

<p align="center">
  <strong>A comprehensive, production-ready machine learning journey from fundamentals to enterprise deployment</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.12+-blue.svg" alt="Python Version"/>
  <img src="https://img.shields.io/badge/PyTorch-2.9+-EE4C2C.svg" alt="PyTorch"/>
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License"/>
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome"/>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Key Highlights](#key-highlights)
- [Repository Structure](#repository-structure)
- [Technologies & Frameworks](#technologies--frameworks)
- [Learning Path](#learning-path)
- [Getting Started](#getting-started)
- [Featured Projects](#featured-projects)
- [Acknowledgments](#acknowledgments)

---

## Overview

This repository contains a comprehensive collection of machine learning implementations, tutorials, and production-ready examples spanning the entire ML/AI stack. From foundational statistics to cutting-edge LLM fine-tuning and production deployment on Kubernetes, this course demonstrates full-stack ML engineering expertise.

**What makes this special:**
- **150+ hands-on notebooks** covering theory and implementation
- **Production-ready examples** with Docker, Kubernetes, and cloud deployment
- **Modern AI topics** including LLMs, RAG systems, diffusion models, and RLHF
- **From scratch implementations** to understand core algorithms
- **Enterprise MLOps** practices with MLflow, KServe, and AWS SageMaker

This repository corresponds to [The Ultimate Machine Learning Course](https://thecuriouscurator.in/course/ultimate-machine-learning-course-recordings-only/) offered by **The Curious Curator**.

---

## Key Highlights

### Deep Learning Architectures
- **9+ CNN architectures** from scratch: LeNet, AlexNet, VGG, GoogLeNet, ResNet, DenseNet
- **RNN variants**: Character-level models, Seq2Seq, attention mechanisms
- **Image Captioning**: CNN+LSTM multimodal architecture
- **Distributed Training**: Multi-GPU with DDP, mixed precision (AMP), CUDA optimization

### Generative AI
- **Diffusion Models**: Training, sampling, conditional generation, fast inference
- **GANs**: Vanilla, DCGAN, Conditional GAN, CycleGAN
- **Variational Autoencoders**: Latent space modeling
- **Transformers**: From scratch implementations, HuggingFace integration

### LLMs & Agent Systems
- **RAG from Scratch**: 18+ notebooks covering query translation, routing, indexing, retrieval
- **LangGraph Academy**: Complete agent framework (24 modules) with memory, human-in-the-loop, sub-graphs
- **Multimodal LLMs**: Gemini API, ColPali document understanding

### Reinforcement Learning
- **Bandit Algorithms**: On/off-policy learning, OPE with real-world ZOZOTOWN data
- **Policy Gradient**: REINFORCE, PPO, A2C with Stable Baselines 3
- **Value-Based**: DQN, SAC, HER (Hindsight Experience Replay)
- **Hyperparameter Tuning**: Optuna integration for RL algorithms
- **Unity ML-Agents**: Training environments and executables

### Probabilistic Programming
- **15+ Pyro tutorials**: Bayesian Data Analysis, MCMC, NUTS sampler
- **Advanced Topics**: Causal inference, multilevel models, Gaussian processes, measurement error
- **Model Comparison**: Information criteria, regularization techniques

### Production & MLOps
- **Model Serving**: MLflow, KServe, TorchServe, ONNX export
- **Kubernetes Deployment**: Complete EKS setup with automated scripts
- **AWS SageMaker**: Training pipelines, real-time endpoints, batch transform, autoscaling

### Classical ML
- **Comprehensive Coverage**: Classification, regression, clustering, ensemble methods
- **From Scratch**: Vanilla Python implementations before scikit-learn
- **Statistical Tests as Linear Models**: Deep dive into the mathematical foundations showing how t-tests, ANOVA, and other statistical tests are special cases of linear models
- **A/B Testing**: Statistical methodology and practical examples
- **Convex Optimization**: CVXPY tutorials for mathematical programming

---

## Repository Structure

```
UltimateMLCourse/
│
├── 📚 Foundations
│   ├── Python/                                    # Software engineering patterns
│   ├── Numpy + Pytorch Primitives/                # Numerical computing fundamentals
│   ├── DataAnalysis + Pandas/                     # Data wrangling and analysis
│   ├── Probability + Statistics/                  # Statistical foundations
│   └── statistical + tests + are + LinearModels/  # ⭐ Statistical tests as linear models (highly recommended)
│
├── 🤖 Classical Machine Learning
│   ├── ML + Classical/                            # Sklearn, clustering, ensembles
│   ├── AB-Test/                                   # Experimental design
│   └── Optimization + cvxpy + julia/              # Mathematical optimization
│
├── 🧠 Deep Learning
│   ├── DL+Pytorch/                                # CNN/RNN architectures (9+ models)
│   ├── Distributed+AMP+TrainingOptimization/      # Multi-GPU training
│   └── OperationalizingModels-Production/         # TorchServe, ONNX, Docker
│
├── 🎨 Generative AI
│   ├── GenAI + Pytorch/Transformer/               # Transformer implementations
│   ├── GenAI + Pytorch/DiffusionModel-sprite/     # Diffusion models (4 labs)
│   ├── GenAI + Pytorch/GAN/                       # GAN variants (4 types)
│   └── GenAI + Pytorch/VariationalAutoencoders/   # VAE implementations
│
├── 🎲 Probabilistic Programming
│   └── ProbabilisticProgramming + BDA (SR)/       # Pyro + Bayesian analysis (15+ notebooks)
│
├── 🎮 Interactive Systems & RL
│   ├── Interactive-Systems/                       # Bandits, PPO, DQN, SAC, Optuna tuning
│   └── GenAI + Pytorch/Transformer/huggingface-LLM-RL/  # Unity ML-Agents environments
│
├── 🤗 LLMs, RAG & Agents
│   ├── LLM-RAG-Agents/rag-from-scratch/          # RAG pipeline (18+ notebooks)
│   ├── LLM-RAG-Agents/LangGraph/                 # Agent frameworks (24 modules)
│   └── LLM-RAG-Agents/LLMs/                      # LLM fundamentals, multimodal
│
├── ☁️ Cloud & Production
│   ├── AWS-DS/Sagemaker + HuggingFace/           # SageMaker workshops (4 complete)
│   ├── serving/                                   # MLflow + KServe + EKS deployment
│   └── Coder->SE/                                 # Software engineering best practices
│
└── 🛠️ Tools & Documentation
    ├── Git/                                       # Git workflows and tutorials
    └── Talks/                                     # Conference materials
```

---

## Technologies & Frameworks

### Core ML/AI Stack
![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?style=flat&logo=pytorch&logoColor=white)
![scikit-learn](https://img.shields.io/badge/scikit--learn-F7931E?style=flat&logo=scikit-learn&logoColor=white)
![TensorFlow](https://img.shields.io/badge/TensorFlow-FF6F00?style=flat&logo=tensorflow&logoColor=white)
![NumPy](https://img.shields.io/badge/NumPy-013243?style=flat&logo=numpy&logoColor=white)
![Pandas](https://img.shields.io/badge/Pandas-150458?style=flat&logo=pandas&logoColor=white)

### LLMs & NLP
![HuggingFace](https://img.shields.io/badge/HuggingFace-FFD21E?style=flat&logo=huggingface&logoColor=black)
![LangChain](https://img.shields.io/badge/LangChain-121212?style=flat&logo=chainlink&logoColor=white)
![OpenAI](https://img.shields.io/badge/OpenAI-412991?style=flat&logo=openai&logoColor=white)

### Production & MLOps
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazon-aws&logoColor=white)
![MLflow](https://img.shields.io/badge/MLflow-0194E2?style=flat&logo=mlflow&logoColor=white)

### Key Libraries
- **Probabilistic Programming**: Pyro, PyMC
- **RL Frameworks**: Stable Baselines 3, Gymnasium
- **Optimization**: CVXPY, Optuna
- **Serving**: TorchServe, KServe, FastAPI
- **Cloud**: SageMaker, EKS, S3

---

## Learning Path

This repository is organized as a progressive learning journey:

```
1. Foundations (4-6 weeks)
   └─→ Python, NumPy, Pandas, Statistics, Statistical Tests as Linear Models ⭐

2. Classical ML (6-8 weeks)
   └─→ Sklearn, Classification, Regression, Clustering, Ensembles

3. Deep Learning Fundamentals (8-10 weeks)
   └─→ CNNs, RNNs, Transfer Learning, Distributed Training

4. Advanced DL & Generative Models (8-10 weeks)
   └─→ GANs, VAEs, Diffusion, Transformers

5. Probabilistic & Causal ML (6-8 weeks)
   └─→ Bayesian Analysis, Pyro, MCMC, Causal Inference

6. Interactive Systems (6-8 weeks)
   └─→ Bandits, Policy Gradient, Model-Based RL, Hyperparameter Tuning

7. Modern LLMs & Agents (8-10 weeks)
   └─→ RAG Systems, LangGraph, Agent Frameworks, LLM Fine-tuning

8. Production & MLOps (6-8 weeks)
   └─→ Model Serving, Kubernetes, AWS, Cloud Deployment
```

**Total Duration**: ~12-18 months for comprehensive coverage

---

## Getting Started

### Prerequisites

- Python 3.12 or higher
- CUDA-capable GPU (recommended for deep learning modules)
- Docker and Kubernetes (for deployment modules)
- AWS account (optional, for cloud modules)

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/UltimateMLCourse.git
cd UltimateMLCourse
```

2. **Set up Python environment** (using uv)
```bash
# Install uv package manager
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install dependencies
uv sync
```

3. **Alternative: Using pip/conda**
```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

4. **Launch Jupyter**
```bash
jupyter lab
```

### Quick Start Examples

**Classical ML:**
```bash
jupyter notebook "ML + Classical/S2-sklearn-classification.ipynb"
```

**Deep Learning:**
```bash
jupyter notebook "DL+Pytorch/S1-from-scratch-mnist.ipynb"
```

**LLM & RAG:**
```bash
jupyter notebook "LLM-RAG-Agents/rag-from-scratch/L1-overview-with-openai-api.ipynb"
```

**Production Deployment:**
```bash
cd serving/L4_EKS_kserve_mlflow
./scripts/setup-eks.sh
```

---

## Featured Projects

### Project 1: End-to-End Image Captioning
**Location**: `DL+Pytorch/S9-cnn-lstm-image-captioning.ipynb`
- CNN encoder + LSTM decoder architecture
- Attention mechanism implementation
- Custom data pipeline for COCO dataset

### Project 2: Production ML on Kubernetes
**Location**: `serving/L4_EKS_kserve_mlflow/`
- Complete MLOps pipeline
- Model versioning with MLflow
- Scalable inference with KServe on EKS
- Automated deployment scripts

### Project 3: RAG System from Scratch
**Location**: `LLM-RAG-Agents/rag-from-scratch/`
- 18 progressive notebooks
- Query translation, routing, and retrieval
- Comparison of OpenAI vs open-source LLMs
- RAPTOR: Recursive tree-organized retrieval

### Project 4: Diffusion Models for Image Generation
**Location**: `GenAI + Pytorch/DiffusionModel-sprite/`
- Training from scratch
- Conditional generation with context
- Fast sampling techniques
- Custom sprite generation

### Project 5: Bayesian Causal Inference
**Location**: `ProbabilisticProgramming + BDA (SR)/Session13a-social-relations-instrumental-variables.ipynb`
- Causal DAGs and d-separation
- Instrumental variables
- Social network analysis
- Gaussian Process regression

---

## Project Statistics

- **Total Notebooks**: 150+
- **Lines of Code**: 50,000+
- **Topics Covered**: 40+
- **Production Projects**: 5 complete end-to-end systems
- **Deep Learning Models**: 25+ architectures implemented
- **Cloud Deployments**: AWS SageMaker, EKS, EC2

---

## Development Tools & Best Practices

This repository follows industry best practices:

- **Code Quality**: Scripts for linting and quality checks
- **Version Control**: Git workflows documented
- **Documentation**: Inline comments and markdown explanations
- **Reproducibility**: Fixed seeds, environment specifications

---

## Contributing

Contributions are welcome! If you'd like to:
- Fix bugs or typos
- Add new tutorials or implementations
- Improve documentation
- Share your insights

Please open an issue or submit a pull request.

---

## Acknowledgments

This repository corresponds to [The Ultimate Machine Learning Course](https://thecuriouscurator.in/course/ultimate-machine-learning-course-recordings-only/) offered by **[The Curious Curator](https://thecuriouscurator.in/)**.

The content represents a curated and enhanced collection of ML implementations, drawing from:
- Course materials from The Curious Curator
- Official PyTorch, HuggingFace, and AWS tutorials
- Research papers and open-source implementations
- Personal projects and production experience

Special thanks to the open-source ML community for the incredible tools and frameworks that make this learning journey possible.

---

## License

This project is licensed under the MIT License - see individual directories for specific attributions.

---

## Contact & Connect

- **GitHub**: [Your GitHub Profile]
- **LinkedIn**: [Your LinkedIn]
- **Email**: [Your Email]
- **Course Website**: [The Curious Curator](https://thecuriouscurator.in/)

---

<p align="center">
  <strong>⭐ If you find this repository helpful, please consider giving it a star! ⭐</strong>
</p>

<p align="center">
  <sub>Built with passion for machine learning and production excellence</sub>
</p>
