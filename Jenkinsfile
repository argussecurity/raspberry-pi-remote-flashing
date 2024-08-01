@Library('itx-jenkins-shared-lib') _
// Find documentation online here:
// http://gitlab.kelle.grp/itx/jenkins-shared-lib/blob/master/README.md

pipeline {
    agent { label 'linux' }
    options {
        gitLabConnection('ithinx gitlab connection')
        gitlabCommitStatus(name: 'jenkins')
    }

    stages {
        stage('Clean') {
            steps {
                cleanWs()
            }
        }
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Build') {
            agent {
                dockerfile {
                    filename '.devcontainer/Dockerfile'
                    dir '.'
                    reuseNode true
                    label 'linux'
                    additionalBuildArgs '--network=host \
                                         --build-arg UID=$(id -u) \
                                         --build-arg GID=$(id -g)'
                    // mounting the ssh folder is a workaround for recursive git checkouts using the west tool
                    args '''
                           --network host \
                           --privileged \
                           -v /dev/mapper:/dev/mapper \
                           -v /dev/loop0:/dev/loop0 \
                           -v $WORKSPACE:/workdir \
                           -v $HOME/.ssh:/home/user/.ssh \
                           -w /workdir
                         '''
                }
            }
            steps {
                sh '''
                     cd recovery_image
                     ./build.sh
                   '''
            }
        }
        stage('Archive') {
            steps {
                dir('recovery_image/artifacts') {
                    archiveArtifacts artifacts: 'recovery.tar.bz2', onlyIfSuccessful: true
                }
            }
        }
    }
    post {
        always {
            // This method from the ithinx shared lib will trigger gitlab, slack, and email depending on result
            triggerNotificationsOnBuild(currentBuild.result, "")

            updateGitlabCommitStatus name: 'jenkins',
                                     state: 'SUCCESS' == currentBuild.result ? 'success' : 'failed'
        }
        success {
            // cleanup workspace to reduce Jenkins footprint (keep sources for browsing)
            cleanWs()
        }
    }
}
