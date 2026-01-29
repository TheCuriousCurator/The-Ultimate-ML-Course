import mlflow
import xgboost as xgb
from dataset import generate_apple_sales_data_with_promo_adjustment
from sklearn.model_selection import train_test_split


mlflow.set_tracking_uri('http://localhost:8080')
loaded = mlflow.xgboost.load_model("models:/xgb-optuna-model/2")

df = generate_apple_sales_data_with_promo_adjustment(base_demand=1_000, n_rows=5000)
# Preprocess the dataset
X = df.drop(columns=["date", "demand"])
y = df["demand"]

train_x, valid_x, train_y, valid_y = train_test_split(X, y, test_size=0.25)
batch_dmatrix = xgb.DMatrix(X)

print(X.iloc[[3]],)

inference = loaded.predict(batch_dmatrix)

infer_df = df.copy()

infer_df["predicted_demand"] = inference