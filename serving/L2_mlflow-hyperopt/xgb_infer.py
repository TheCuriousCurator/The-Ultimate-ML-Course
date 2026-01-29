import requests

# Use MLFlow's /invocations endpoint which properly handles pandas DataFrames
url = "http://localhost:8080/invocations"

# Send data as pandas DataFrame in split format with column names
payload = {
    "dataframe_split": {
        "columns": [
            "average_temperature",
            "rainfall",
            "weekend",
            "holiday",
            "price_per_kg",
            "promo",
            "previous_days_demand",
            "competitor_price_per_kg",
            "marketing_intensity"
        ],
        "data": [
            [23.56940827375469, 12.544953937777112, 0, 0, 1.6773482910369293, 0, 1122.4260011785589, 0.6847261534378208, 0.8409025538720792]
        ]
    }
}

headers = {"Content-Type": "application/json"}
response = requests.post(url, json=payload, headers=headers)

print(response.text)
