import mlflow

import numpy as np
from sklearn import datasets, metrics
from sklearn.linear_model import ElasticNet
from sklearn.model_selection import train_test_split, RandomizedSearchCV
from scipy.stats import uniform


def eval_metrics(pred, actual):
    rmse = np.sqrt(metrics.mean_squared_error(actual, pred))
    mae = metrics.mean_absolute_error(actual, pred)
    r2 = metrics.r2_score(actual, pred)
    return rmse, mae, r2


mlflow.set_tracking_uri('http://localhost:5000')

mlflow.set_experiment("wine-quality")

# Set th experiment name
mlflow.set_experiment("wine-quality")

# Enable auto-logging to MLflow
mlflow.sklearn.autolog(log_model_signatures=True, registered_model_name="wine-quality-elasticnet")

# Load wine quality dataset
X, y = datasets.load_wine(return_X_y=True)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.25)

# Start a run and train a model
with mlflow.start_run(run_name="default-params"):
    lr = ElasticNet()
    lr.fit(X_train, y_train)

    y_pred = lr.predict(X_test)
    rmse, mae, r2 = eval_metrics(y_pred, y_test)
