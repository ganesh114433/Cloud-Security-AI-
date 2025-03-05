from google.cloud import aiplatform, bigquery
import base64
import json
from datetime import datetime

# Initialize Vertex AI Endpoint
endpoint = aiplatform.Endpoint(endpoint_name="projects/YOUR_PROJECT_ID/locations/YOUR_REGION/endpoints/YOUR_ENDPOINT_ID")

# Initialize BigQuery client
bq_client = bigquery.Client()
table_id = "YOUR_PROJECT_ID.network_logs.predictions"

def log_processor(event, context):
    # Decode Pub/Sub message
    message = base64.b64decode(event['data']).decode('utf-8')
    log_data = json.loads(message)

    # Preprocess log
    features = [
        log_data.get("duration", 0),
        log_data.get("protocol_type", 0),
        log_data.get("service", 0),
        log_data.get("flag", 0),
        log_data.get("src_bytes", 0),
        log_data.get("dst_bytes", 0)
    ]

    # Get prediction from Vertex AI
    prediction = endpoint.predict(instances=[features]).predictions[0]

    # Save to BigQuery
    rows_to_insert = [
        {
            "timestamp": datetime.utcnow().isoformat(),
            "log": json.dumps(log_data),
            "prediction": prediction
        }
    ]
    bq_client.insert_rows_json(table_id, rows_to_insert)
