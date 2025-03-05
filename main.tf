# Configure the Google Cloud provider
provider "google" {
  project = "YOUR_PROJECT_ID"
  region  = "YOUR_REGION"
}

# Enable required APIs
resource "google_project_service" "services" {
  for_each = toset([
    "aiplatform.googleapis.com",  # Vertex AI API
    "logging.googleapis.com",     # Cloud Logging API
    "cloudbuild.googleapis.com",  # Cloud Build API (for Pipelines)
    "storage.googleapis.com"      # Cloud Storage API
  ])
  project = "YOUR_PROJECT_ID"
  service = each.value
}

# Create a Cloud Storage bucket for data storage
resource "google_storage_bucket" "data_bucket" {
  name          = "vertex-ai-data-bucket-${random_id.bucket_id.hex}"
  location      = "YOUR_REGION"
  storage_class = "STANDARD"
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

# Create a Vertex AI pipeline artifact bucket
resource "google_storage_bucket" "pipeline_bucket" {
  name          = "vertex-ai-pipeline-artifacts-${random_id.pipeline_id.hex}"
  location      = "YOUR_REGION"
  storage_class = "STANDARD"
}

resource "random_id" "pipeline_id" {
  byte_length = 4
}

# Create a Pub/Sub topic for real-time log streaming
resource "google_pubsub_topic" "log_topic" {
  name = "vertex-ai-log-stream"
}

# Create a Pub/Sub subscription for log processing
resource "google_pubsub_subscription" "log_subscription" {
  name  = "vertex-ai-log-subscription"
  topic = google_pubsub_topic.log_topic.name
}

# Vertex AI Endpoint for Model Deployment
resource "google_vertex_ai_endpoint" "endpoint" {
  display_name = "anomaly-detection-endpoint"
  region       = "YOUR_REGION"
}

# Vertex AI Model Deployment
resource "google_vertex_ai_model_deployment" "model" {
  endpoint      = google_vertex_ai_endpoint.endpoint.name
  model         = "YOUR_MODEL_ID"  # Replace with your pre-trained model ID
  min_replicas  = 1
  max_replicas  = 3
}

# IAM Roles for Logging and Vertex AI
resource "google_project_iam_member" "vertex_ai_roles" {
  for_each = toset([
    "roles/aiplatform.user",      # For accessing Vertex AI
    "roles/logging.viewer",       # For accessing logs
    "roles/storage.objectAdmin"   # For storage bucket access
  ])
  project = "YOUR_PROJECT_ID"
  member  = "serviceAccount:YOUR_SERVICE_ACCOUNT"
  role    = each.value
}
# BigQuery Dataset for Reports
resource "google_bigquery_dataset" "network_logs" {
  dataset_id = "network_logs"
  location   = "YOUR_REGION"
}

# BigQuery Table for storing predictions
resource "google_bigquery_table" "predictions_table" {
  dataset_id = google_bigquery_dataset.network_logs.dataset_id
  table_id   = "predictions"
  schema     = <<EOF
[
  {"name": "timestamp", "type": "TIMESTAMP", "mode": "REQUIRED"},
  {"name": "log", "type": "STRING", "mode": "REQUIRED"},
  {"name": "prediction", "type": "STRING", "mode": "REQUIRED"}
]
EOF
}

# Pub/Sub topic for streaming logs
resource "google_pubsub_topic" "logs_topic" {
  name = "streaming-logs-topic"
}
resource "google_cloudfunctions2_function" "log_processor" {
  name     = "log-processor"
  location = "YOUR_GCP_REGION" # e.g., us-central1
  build_config {
    runtime     = "python39"
    entry_point = "log_processor" # Function name from your Python code
    source {
      storage_source {
        bucket = google_storage_bucket.cloud_function_source_bucket.name
        object = google_storage_bucket_object.cloud_function_source_zip.name
      }
    }
  }
  service_config {
    max_instance_count = 3 # Adjust based on expected load
    timeout_seconds  = 60 # Adjust as needed
    available_memory = "256Mi" # Adjust as needed
    environment_variables = {
      PROJECT_ID      = "YOUR_PROJECT_ID",
      ENDPOINT_ID     = "YOUR_ENDPOINT_ID",
      REGION          = "YOUR_GCP_REGION",
      BIGQUERY_DATASET = "YOUR_BIGQUERY_DATASET", #e.g., network_logs
    }
    all_traffic_on_latest_revision = true
  }
  event_trigger {
    trigger_region = "YOUR_GCP_REGION" # Must match function location
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.streaming_logs_topic.id # Trigger on your Pub/Sub topic
  }
}

resource "google_storage_bucket" "cloud_function_source_bucket" {
  name     = "log-processor-source"
  location = "YOUR_GCP_REGION" # Must match function location
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "cloud_function_source_zip" {
  name   = "source.zip" # Name of your zipped source code
  bucket = google_storage_bucket.cloud_function_source_bucket.name
  source = "source.zip" # Path to your zipped source code on your local machine
}

