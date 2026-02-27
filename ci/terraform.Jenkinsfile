// ci/terraform.Jenkinsfile
// Applies Terraform SLOs and dashboards to Grafana Cloud.
//
// Triggered automatically by ci/deploy.Jenkinsfile after a successful Helm
// deploy, or manually from the Jenkins UI.
//
// Requires agent label 'terraform' (configured via JCasC in jenkins/values.yaml):
//   - jnlp container: Jenkins agent (clones repo from GitHub into workspace)
//   - terraform container: hashicorp/terraform:1.9
//
// Grafana credentials are injected from the 'grafana-credentials' k8s Secret
// as TF_VAR_grafana_url and TF_VAR_grafana_api_key environment variables.
// State is stored in a Kubernetes Secret (backend "kubernetes" in main.tf).

pipeline {
  agent { label 'terraform' }

  options {
    timeout(time: 10, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }

  stages {

    stage('Init') {
      steps {
        container('terraform') {
          dir('terraform') {
            sh 'terraform init -input=false -backend-config="in_cluster_config=true"'
          }
        }
      }
    }

    stage('Plan') {
      steps {
        container('terraform') {
          dir('terraform') {
            sh 'terraform plan -input=false -out=tfplan'
          }
        }
      }
    }

    stage('Apply') {
      steps {
        container('terraform') {
          dir('terraform') {
            sh 'terraform apply -input=false -auto-approve tfplan'
          }
        }
      }
    }

  }

  post {
    success {
      echo "Terraform apply completed — SLOs and dashboards synced to Grafana Cloud."
    }
    failure {
      echo "Terraform apply failed. Check the plan output above."
    }
  }
}
