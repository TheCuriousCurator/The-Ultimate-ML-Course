from mlserver_mlflow import MLflowRuntime
from mlserver.types import InferenceRequest, InferenceResponse
from mlserver.codecs import NumpyCodec
import numpy as np
import pandas as pd


class XGBoostMLflowRuntime(MLflowRuntime):
    """Custom runtime for XGBoost models that properly handles input decoding."""

    async def predict(self, payload: InferenceRequest) -> InferenceResponse:
        """
        Override predict to ensure proper decoding of the input payload.

        The standard MLflowRuntime sometimes fails to decode the payload properly
        for XGBoost models, so we explicitly decode it here.
        """
        # Decode the payload to numpy array
        decoded_payload = self.decode_request(payload)

        # Call the parent's predict method with the decoded payload
        # But we need to use the internal _model directly since parent expects decoded data
        model_output = self._model.predict(decoded_payload)

        # Encode the response
        return self.encode_response(payload, model_output)

    def decode_request(self, payload: InferenceRequest):
        """Decode the inference request to the format expected by the model."""
        # Use NumpyCodec to decode the input
        codec = NumpyCodec()

        # Decode all inputs
        decoded_inputs = []
        for input_data in payload.inputs:
            decoded = codec.decode_input(input_data)
            decoded_inputs.append(decoded)

        # For a single input, use it directly
        if len(decoded_inputs) == 1:
            data = decoded_inputs[0]
        else:
            # For multiple inputs, concatenate them
            data = np.concatenate(decoded_inputs, axis=1)

        # Convert to DataFrame with feature names expected by XGBoost
        feature_names = [
            'average_temperature',
            'rainfall',
            'weekend',
            'holiday',
            'price_per_kg',
            'promo',
            'previous_days_demand',
            'competitor_price_per_kg',
            'marketing_intensity'
        ]

        return pd.DataFrame(data, columns=feature_names)

    def encode_response(self, request: InferenceRequest, model_output) -> InferenceResponse:
        """Encode the model output as an inference response."""
        # Convert output to numpy array if needed
        if not isinstance(model_output, np.ndarray):
            model_output = np.array(model_output)

        # Ensure 2D shape for encoding
        if model_output.ndim == 1:
            model_output = model_output.reshape(-1, 1)

        # Use NumpyCodec to encode the output
        codec = NumpyCodec()
        outputs = [codec.encode_output(
            name="predict",
            payload=model_output,
            use_bytes=False
        )]

        return InferenceResponse(
            model_name=self.name,
            outputs=outputs
        )
