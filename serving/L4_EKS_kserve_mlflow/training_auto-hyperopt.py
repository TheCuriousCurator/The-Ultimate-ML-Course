# https://mlflow.org/docs/latest/ml/deployment/deploy-model-to-kubernetes/tutorial/
# https://kserve.github.io/website/docs/getting-started/predictive-first-isvc

from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

import mlflow
import os
import numpy as np
from sklearn import datasets, metrics
from sklearn.linear_model import ElasticNet
from sklearn.model_selection import train_test_split, RandomizedSearchCV
from scipy.stats import uniform
from urllib.parse import urlparse

MLFLOW_TRACKING_URI = os.environ.get("MLFLOW_TRACKING_URI")
MLFLOW_REGISTRY_URI = os.environ.get("MLFLOW_REGISTRY_URI")

def eval_metrics(pred, actual):
    rmse = np.sqrt(metrics.mean_squared_error(actual, pred))
    mae = metrics.mean_absolute_error(actual, pred)
    r2 = metrics.r2_score(actual, pred)
    return rmse, mae, r2


# mlflow.set_tracking_uri('http://localhost:5000')
mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)
# Set registry URI to use standard model registry (not Unity Catalog)
mlflow.set_registry_uri(MLFLOW_REGISTRY_URI)
tracking_url_type_store = urlparse(mlflow.get_tracking_uri()).scheme
print(f"{tracking_url_type_store=}")
# Set th experiment name
mlflow.set_experiment("wine-quality-2")
# Enable auto-logging to MLflow
mlflow.sklearn.autolog(log_model_signatures=True, registered_model_name="wine-quality-elasticnet")

# Load wine quality dataset
X, y = datasets.load_wine(return_X_y=True)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.25)


lr = ElasticNet()

# Define distribution to pick parameter values from
distributions = dict(
    alpha=uniform(loc=0, scale=10),  # sample alpha uniformly from [-5.0, 5.0]
    l1_ratio=uniform(),  # sample l1_ratio uniformlyfrom [0, 1.0]
)

# Initialize random search instance
clf = RandomizedSearchCV(
    estimator=lr,
    param_distributions=distributions,
    # Optimize for mean absolute error
    scoring="neg_mean_absolute_error",
    # Use 5-fold cross validation
    cv=5,
    # Try 100 samples. Note that MLflow only logs the top 5 runs.
    n_iter=100,
)

# Start a parent run
with mlflow.start_run(run_name="hyperparameter-tuning") as run:
    search = clf.fit(X_train, y_train)

    # Evaluate the best model on test dataset
    y_pred = clf.best_estimator_.predict(X_test)
    rmse, mae, r2 = eval_metrics(y_pred, y_test)
    mlflow.log_metrics(
        {
            "mean_squared_error_X_test": rmse,
            "mean_absolute_error_X_test": mae,
            "r2_score_X_test": r2,
        }
    )

    # Get the run ID for the best model
    run_id = run.info.run_id
    print(f"Best model run ID: {run_id}")

# Get the latest version of the registered model
import subprocess
import os

client = mlflow.tracking.MlflowClient()
model_name = "wine-quality-elasticnet"

# Get all versions of the model and find the latest
try:
    model_versions = client.search_model_versions(f"name='{model_name}'")
    if model_versions:
        # Sort by version number (descending) to get the latest
        latest_version = max(int(mv.version) for mv in model_versions)
    else:
        latest_version = None
except Exception as e:
    print(f"Error retrieving model versions: {e}")
    latest_version = None

if latest_version:
    model_uri = f"models:/{model_name}/{latest_version}"
    print(f"Building Docker image for model: {model_uri}")

    base_image_name = f"wine-quality-elasticnet-base:{latest_version}"

    # Step 1: Build base Docker image with MLServer enabled
    mlflow.models.build_docker(
        model_uri=model_uri,
        name=base_image_name,
        enable_mlserver=True,
    )
    print(f"Base Docker image '{base_image_name}' built successfully!")
    '''
        # Step 2: Build extended image with MLServer configuration
        final_image_name = f"dksahuji/wine-quality-elasticnet:{latest_version}"
        docker_config_dir = "./L3_kubernetes_kserve_mlflow/docker_config"

        build_cmd = [
            "docker", "build",
            "--build-arg", f"BASE_IMAGE={base_image_name}",
            "-t", final_image_name,
            "-f", f"{docker_config_dir}/Dockerfile",
            docker_config_dir
        ]

        print(f"Building extended Docker image with MLServer config...")
        result = subprocess.run(build_cmd, capture_output=True, text=True)

        if result.returncode == 0:
            print(f"Extended Docker image '{final_image_name}' built successfully!")
            print(f"\nTo push the image, run:")
            print(f"  docker push {final_image_name}")
            print(f"\nTo update the Kubernetes deployment:")
            print(f"  Update manifests/inference.yaml with image: {final_image_name}")
        else:
            print(f"Error building extended Docker image:")
            print(result.stderr)
    '''
else:
    print(f"No model versions found for {model_name}")
