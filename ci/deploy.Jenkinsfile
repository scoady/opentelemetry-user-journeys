// ci/deploy.Jenkinsfile
// Parameterized pipeline: runs `helm upgrade` to deploy TechMart with the
// specified image tag from the in-cluster registry.
//
// Triggered automatically by ci/build.Jenkinsfile (with IMAGE_TAG set to the
// just-built git SHA), or manually from the Jenkins UI with any tag.
//
// Requires agent label 'helm' (configured via JCasC in jenkins/values.yaml):
//   - jnlp container: Jenkins agent (clones repo from GitHub into workspace)
//   - helm container: alpine/helm:3.16.4 (includes both helm and kubectl)

def REGISTRY = "registry.registry.svc.cluster.local:5000"

pipeline {
  agent { label 'helm' }

  parameters {
    string(
      name: 'IMAGE_TAG',
      defaultValue: 'latest',
      description: 'Image tag to deploy — git SHA (e.g. a1b2c3d) or SHA-dev'
    )
  }

  options {
    timeout(time: 15, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
    disableConcurrentBuilds()
  }

  stages {

    stage('Validate') {
      steps {
        script {
          if (!params.IMAGE_TAG?.trim()) {
            error("IMAGE_TAG parameter is required")
          }
          echo "Deploying TechMart tag=${params.IMAGE_TAG} from registry=${REGISTRY}"
          currentBuild.description = "tag=${params.IMAGE_TAG}"
        }
      }
    }

    // ── Helm upgrade ───────────────────────────────────────────────────────
    // global.imageRegistry prefixes all image references with the in-cluster
    // registry address (see infrastructure/helm/techmart/values.yaml).
    // pullPolicy=Always ensures nodes fetch the freshly-pushed image rather
    // than serving a cached layer under the same SHA tag.
    stage('Helm upgrade') {
      steps {
        container('helm') {
          sh """
            helm upgrade techmart ${WORKSPACE}/infrastructure/helm/techmart \\
              --namespace webstore \\
              --create-namespace \\
              --values ${WORKSPACE}/infrastructure/helm/techmart/values.yaml \\
              --set global.imageRegistry=${REGISTRY} \\
              --set api.image.repository=webstore/api \\
              --set api.image.tag=${params.IMAGE_TAG} \\
              --set api.image.pullPolicy=Always \\
              --set inventorySvc.image.repository=webstore/inventory-svc \\
              --set inventorySvc.image.tag=${params.IMAGE_TAG} \\
              --set inventorySvc.image.pullPolicy=Always \\
              --set frontend.image.repository=webstore/frontend \\
              --set frontend.image.tag=${params.IMAGE_TAG} \\
              --set frontend.image.pullPolicy=Always \\
              --wait \\
              --timeout 5m
          """
        }
      }
    }

    stage('Verify rollout') {
      steps {
        container('helm') {
          sh """
            kubectl rollout status deployment/api           -n webstore --timeout=120s
            kubectl rollout status deployment/inventory-svc -n webstore --timeout=120s
            kubectl rollout status deployment/frontend      -n webstore --timeout=120s
          """
        }
      }
    }

  }

  post {
    success {
      echo "TechMart deployed successfully. Tag: ${params.IMAGE_TAG}"
      echo "Store: http://localhost"
    }
    failure {
      echo "Deployment failed for tag=${params.IMAGE_TAG}."
      // Print recent helm history to aid debugging
      sh "helm history techmart -n webstore --max 5 || true"
    }
  }
}
