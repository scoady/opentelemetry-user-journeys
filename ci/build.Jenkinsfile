// ci/build.Jenkinsfile
// Builds api, inventory-svc, and frontend images with Kaniko and pushes them
// to the in-cluster Docker registry, then triggers the deploy pipeline.
//
// Requires agent label 'kaniko' (configured via JCasC in jenkins/values.yaml):
//   - jnlp container: Jenkins agent (clones repo from GitHub into workspace)
//   - kaniko container: gcr.io/kaniko-project/executor:v1.23.2-debug
//   - Both share an emptyDir workspace volume for build context

def REGISTRY = "registry.registry.svc.cluster.local:5000"
def IMAGE_TAG = ""

pipeline {
  agent { label 'kaniko' }

  options {
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '10'))
    disableConcurrentBuilds()
  }

  stages {

    // ── Stage 1: Compute image tag ─────────────────────────────────────────
    // Reads the git SHA from the SCM-checked-out workspace.
    // Appends -dev if the working tree has uncommitted changes.
    stage('Tag') {
      steps {
        script {
          def sha = sh(
            script: "git rev-parse --short HEAD",
            returnStdout: true
          ).trim()
          def dirty = sh(
            script: "git status --porcelain 2>/dev/null | wc -l | tr -d ' '",
            returnStdout: true
          ).trim()
          IMAGE_TAG = (dirty != "0") ? "${sha}-dev" : sha
          echo "Image tag: ${IMAGE_TAG}"
          currentBuild.description = "tag=${IMAGE_TAG}"
        }
      }
    }

    // ── Stage 2: Build and push (3 images) ────────────────────────────────
    // Each stage calls the kaniko executor directly from the sidecar container.
    // --context uses the workspace directory checked out by the SCM step.
    // --insecure / --skip-tls-verify allow plain-HTTP access to the in-cluster
    //   registry (which has no TLS certificate in this local dev setup).
    // Both SHA tag and :latest are pushed so `helm upgrade` can use either.
    stage('Build images') {
      parallel {

        stage('api') {
          steps {
            container('kaniko') {
              sh """
                /kaniko/executor \\
                  --dockerfile=${WORKSPACE}/api/Dockerfile \\
                  --context=dir://${WORKSPACE}/api \\
                  --destination=${REGISTRY}/webstore/api:${IMAGE_TAG} \\
                  --destination=${REGISTRY}/webstore/api:latest \\
                  --insecure \\
                  --insecure-pull \\
                  --skip-tls-verify \\
                  --skip-tls-verify-pull \\
                  --cache=false \\
                  --verbosity=info
              """
            }
          }
        }

        stage('inventory-svc') {
          steps {
            container('kaniko') {
              sh """
                /kaniko/executor \\
                  --dockerfile=${WORKSPACE}/inventory-svc/Dockerfile \\
                  --context=dir://${WORKSPACE}/inventory-svc \\
                  --destination=${REGISTRY}/webstore/inventory-svc:${IMAGE_TAG} \\
                  --destination=${REGISTRY}/webstore/inventory-svc:latest \\
                  --insecure \\
                  --insecure-pull \\
                  --skip-tls-verify \\
                  --skip-tls-verify-pull \\
                  --cache=false \\
                  --verbosity=info
              """
            }
          }
        }

        stage('frontend') {
          steps {
            container('kaniko') {
              sh """
                /kaniko/executor \\
                  --dockerfile=${WORKSPACE}/frontend/Dockerfile \\
                  --context=dir://${WORKSPACE}/frontend \\
                  --destination=${REGISTRY}/webstore/frontend:${IMAGE_TAG} \\
                  --destination=${REGISTRY}/webstore/frontend:latest \\
                  --insecure \\
                  --insecure-pull \\
                  --skip-tls-verify \\
                  --skip-tls-verify-pull \\
                  --cache=false \\
                  --verbosity=info
              """
            }
          }
        }

      } // end parallel
    }

    // ── Stage 3: Trigger deploy ────────────────────────────────────────────
    // Blocks until techmart-deploy completes and propagates its status.
    stage('Deploy') {
      steps {
        script {
          echo "Triggering techmart-deploy with IMAGE_TAG=${IMAGE_TAG}"
          build(
            job: 'techmart-deploy',
            parameters: [
              string(name: 'IMAGE_TAG', value: IMAGE_TAG)
            ],
            wait: true,
            propagate: true
          )
        }
      }
    }

  }

  post {
    success {
      echo "Build and deploy complete. Images: ${REGISTRY}/webstore/*:${IMAGE_TAG}"
    }
    failure {
      echo "Build failed. Review Kaniko output above for details."
    }
  }
}
