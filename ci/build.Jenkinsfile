// ci/build.Jenkinsfile
// Builds api, inventory-svc, and frontend images with Kaniko and pushes them
// to the in-cluster Docker registry, then triggers the deploy pipeline.
//
// Requires agent label 'kaniko' (configured via JCasC in jenkins/values.yaml):
//   - jnlp container: Jenkins agent
//   - kaniko container: gcr.io/kaniko-project/executor:v1.23.2-debug
//   - Both share an emptyDir workspace; /src/repo hostPath mount for build context

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
    // Reads the git SHA from the hostPath-mounted repo (/src/repo).
    // Appends -dev if the working tree has uncommitted changes.
    stage('Tag') {
      steps {
        script {
          def sha = sh(
            script: "git -C /src/repo rev-parse --short HEAD",
            returnStdout: true
          ).trim()
          def dirty = sh(
            script: "git -C /src/repo status --porcelain 2>/dev/null | wc -l | tr -d ' '",
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
    // --context=dir:///src/repo/<service>  uses Kaniko's dir:// scheme to build
    //   from the hostPath-mounted directory (three slashes = dir:// + abs path).
    // --insecure / --skip-tls-verify allow plain-HTTP access to the in-cluster
    //   registry (which has no TLS certificate in this local dev setup).
    // Both SHA tag and :latest are pushed so `helm upgrade` can use either.
    // Note: the three parallel stages share one kaniko container — they are
    //   serialized within the pod. For true parallelism, declare
    //   `agent { label 'kaniko' }` inside each parallel branch (spawns 3 pods).
    stage('Build images') {
      parallel {

        stage('api') {
          steps {
            container('kaniko') {
              sh """
                /kaniko/executor \\
                  --dockerfile=/src/repo/api/Dockerfile \\
                  --context=dir:///src/repo/api \\
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
                  --dockerfile=/src/repo/inventory-svc/Dockerfile \\
                  --context=dir:///src/repo/inventory-svc \\
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
                  --dockerfile=/src/repo/frontend/Dockerfile \\
                  --context=dir:///src/repo/frontend \\
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
