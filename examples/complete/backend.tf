terraform {
  backend "gcs" {
    bucket = "my-gcp-project-tfstate"
    prefix = "clusters-example-c1-monitoring"
  }
}
