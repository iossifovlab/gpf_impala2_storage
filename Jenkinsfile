pipeline {
  agent { label 'piglet' }
  options {
    copyArtifactPermission('/iossifovlab/*,/seqpipe/*');
    disableConcurrentBuilds()
  }
  environment {
    BUILD_SCRIPTS_BUILD_DOCKER_REGISTRY_USERNAME = credentials('jenkins-registry.seqpipe.org.user')
    BUILD_SCRIPTS_BUILD_DOCKER_REGISTRY_PASSWORD_FILE = credentials('jenkins-registry.seqpipe.org.passwd')
    SONARQUBE_DEFAULT_TOKEN=credentials('sonarqube-default')
  }

  stages {
    stage('Start') {
      steps {
        zulipSend(
          message: "Started build #${env.BUILD_NUMBER} of project ${env.JOB_NAME} (${env.BUILD_URL})",
          topic: "${env.JOB_NAME}")
      }
    }
    stage('Generate stages') {
      steps {
        sh "./build.sh preset:slow build_no:${env.BUILD_NUMBER} generate_jenkins_init:yes"
        script {
          load('Jenkinsfile.generated-stages')
        }
      }
    }
  }
  post {
    always {
      script {
        try {
          resultBeforeTests = currentBuild.currentResult
          junit 'test-results/impala-storage-junit.xml, test-results/impala1-storage-integration-junit.xml, test-results/impala2-storage-integration-junit.xml'
          sh "test ${resultBeforeTests} == ${currentBuild.currentResult}"

        //   cobertura coberturaReportFile: 'test-results/coverage.xml',
        //     enableNewApi: false, onlyStable: false, sourceEncoding: 'ASCII'

        //   recordIssues(
        //     enabledForFailure: true, aggregatingResults: false,
        //     tools: [
        //       flake8(pattern: 'test-results/flake8_report', reportEncoding: 'UTF-8'),
        //       myPy(pattern: 'test-results/mypy_dae_report', reportEncoding: 'UTF-8', id: 'mypy-dae', name: 'MyPy - dae'),
        //       myPy(pattern: 'test-results/mypy_wdae_report', reportEncoding: 'UTF-8', id: 'mypy-wdae', name: 'MyPy - wdae'),
        //       pyLint(pattern: 'test-results/pylint_gpf_report', reportEncoding: 'UTF-8')
        //     ],
        //     qualityGates: [[threshold: 1, type: 'DELTA', unstable: true]]
        //   )

        //   publishHTML (target : [allowMissing: true,
        //     alwaysLinkToLastBuild: true,
        //     keepAll: true,
        //     reportDir: 'test-results/coverage-html',
        //     reportFiles: 'index.html',
        //     reportName: 'gpf-coverage-report',
        //     reportTitles: 'gpf-coverage-report'])

        } finally {
          zulipNotification(
            topic: "${env.JOB_NAME}"
          )
        }
      }
    }
    unstable {
      script {
        load('build-scripts/libjenkinsfile/zulip-tagged-notification.groovy').zulipTaggedNotification()
      }
    }
    failure {
      script {
        load('build-scripts/libjenkinsfile/zulip-tagged-notification.groovy').zulipTaggedNotification()
      }
    }
  }
}