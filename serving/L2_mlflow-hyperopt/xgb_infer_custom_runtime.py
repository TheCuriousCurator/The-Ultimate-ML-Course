"""
model-settings.json
{
    "name": "mlflow-hyperopt",
    "implementation": "runtime.XGBoostMLflowRuntime",
    "parameters": {
      "uri": "models:/xgb-optuna-model/6"
    },
    "max_batch_size": 128,
    "max_batch_time": 0.1
  }


"""
import requests

url = "http://localhost:8080/v2/models/mlflow-hyperopt/infer"

payload = {
    "inputs": [
        {
            "name": "input",
            "shape": [1,9],
            "datatype": "FP32",
            "data": [23.56940827375469, 12.544953937777112, 0, 0, 1.6773482910369293, 0, 1122.4260011785589, 0.6847261534378208, 0.8409025538720792]
        }
    ]
}

headers = {"Content-Type": "application/json"}
response = requests.post(url, json=payload, headers=headers)

print(response.text)
