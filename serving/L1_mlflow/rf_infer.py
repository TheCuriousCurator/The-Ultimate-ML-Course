import requests

url = "http://localhost:8080/v2/models/mlflow/infer"

payload = {
    "inputs": [
        {
          "name": "input",
          "shape": [1, 4],
          "datatype": "FP64",
          "data": [6.3, 2.5, 5.0, 1.9]
        }
    ]
}

headers = {"Content-Type": "application/json"}


response = requests.post(url, json=payload, headers=headers)

print(response.text)
