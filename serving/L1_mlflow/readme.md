
pip install virtualenv
cd /home/mb600l/.pyenv/plugins/python-build/../.. && git pull && cd -
/home/mb600l/.pyenv/bin/pyenv install --skip-existing  3.12.10

### Example Commands

  # Serve a registered model
  mlflow models serve -m "models:/my-model/Production" -p 5000

  # Serve from a run
  mlflow models serve -m "runs:/abc123def456/model" -p 8080

  # Serve with multiple workers
  mlflow models serve -m "models:/sk-learn-random-forest-reg-model/4" -p 5000 -w 4

  # Serve on all network interfaces
  mlflow models serve -m "file:///path/to/model" -h 0.0.0.0 -p 5000

  Making Predictions

  Once served, you can make predictions via POST requests:

curl -X POST http://127.0.0.1:5000/invocations \
-H 'Content-Type:application/json' \ 
-d '{"inputs": [[1, 2, 3, 6]]}'

curl -X POST http://localhost:8080/v2/models/mlflow/infer \
    -H 'Content-Type: application/json' \
    -d '{
      "inputs": [
        {
          "name": "input-0",
          "shape": [1, 4],
          "datatype": "FP64",
          "data": [6.3, 2.5, 5.0, 1.9]
        }
      ]
    }'

# Check ready status with verbose output
  curl -v http://localhost:8080/v2/health/ready

  # Check live status
  curl -v http://localhost:8080/v2/health/live

  # Alternative: see just the HTTP status code
  curl -w "\nHTTP Status: %{http_code}\n" http://localhost:8080/v2/health/ready
