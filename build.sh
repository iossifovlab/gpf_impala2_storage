#!/bin/bash

shopt -s extdebug
shopt -s inherit_errexit
set -e

. build-scripts/loader-extended.bash

loader_addpath build-scripts/

# shellcheck source=build-scripts/libmain.sh
include libmain.sh
# shellcheck source=build-scripts/libbuild.sh
include libbuild.sh
# shellcheck source=build-scripts/libdefer.sh
include libdefer.sh
# shellcheck source=build-scripts/liblog.sh
include liblog.sh
# shellcheck source=build-scripts/libopt.sh
include libopt.sh

function main() {
  local -A options
  libopt_parse options \
    stage:all preset:fast clobber:allow_if_matching_values build_no:0 \
    generate_jenkins_init:no expose_ports:no -- "$@"

  local preset="${options["preset"]}"
  local stage="${options["stage"]}"
  local clobber="${options["clobber"]}"
  local build_no="${options["build_no"]}"
  local generate_jenkins_init="${options["generate_jenkins_init"]}"
  local expose_ports="${options["expose_ports"]}"

  libmain_init iossifovlab.gpf_impala_storage gpf_impala_storage
  libmain_init_build_env \
    clobber:"$clobber" preset:"$preset" build_no:"$build_no" \
    generate_jenkins_init:"$generate_jenkins_init" \
    expose_ports:"$expose_ports" \
    iossifovlab.gpf

  libmain_save_build_env_on_exit
  libbuild_init stage:"$stage" registry.seqpipe.org

  build_run_ctx_init "local"
  defer_ret build_run_ctx_reset

  build_stage "Cleanup"
  {

    build_run_ctx_init "container" "ubuntu:22.04"
    defer_ret build_run_ctx_reset

    build_run rm -rvf ./build-env/*.yaml
    build_run rm -rf /wd/results /wd/sources /wd/channel

    build_run_local mkdir -p results

  }

#   build_stage "Clone projects"
#   {
#     build_run_local mkdir -p projects

#     # the quotes around 'EOF' are signifcant - it forces bash to treat the string as literal string until EOF
#     build_run_local bash -e -x <<'EOF'
#         project_name="iossifovlab.gpf"
#         if ! [ -d "projects/$project_name.repo" ]; then
#           git clone "ssh://git@github.com/${project_name/.//}" "projects/$project_name.repo"
#         fi
# EOF

#     # the quotes around 'EOF' are signifcant - it forces bash to treat the string as literal string until EOF
#     build_run_local env gpf_git_describe="$(e gpf_git_describe)" gpf_git_branch="$(e gpf_git_branch)" bash -e -x << 'EOF'

#         project_name="iossifovlab.gpf"
#         project_repo_dirname="iossifovlab.gpf.repo"

#         cd "projects/$project_repo_dirname"
#         git checkout $gpf_git_branch
#         git pull --ff-only

#         git checkout "$gpf_git_describe"
#         cd -
# EOF

#   }

  local gpf_impala_storage_image="gpf-impala-storage-dev"
  local gpf_impala_storage_image_ref
  # create gpf docker image
  build_stage "Create gpf_impala_storage docker image"
  {
    build_run_local cd projects/iossifovlab.gpf.repo/impala_storage
    build_run_local ls -l

    local gpf_dev_tag
    gpf_dev_tag="$(e docker_img_gpf_dev_tag)"
    build_docker_image_create "$gpf_impala_storage_image" . ./Dockerfile "$gpf_dev_tag"
    gpf_impala_storage_image_ref="$(e gpf_impala_storage_image)"

    build_run_local cd -
    build_run_local pwd
    build_run_local ls -l
  }

  build_stage "Create network"
  {
    # create network
    local -A ctx_network
    build_run_ctx_init ctx:ctx_network "persistent" "network"
    build_run_ctx_persist ctx:ctx_network
  }

  # run impala
  build_stage "Run impala"
  {
    local -A ctx_impala
    build_run_ctx_init ctx:ctx_impala "persistent" "container" "seqpipe/seqpipe-docker-impala:latest" \
        "cmd-from-image" "no-def-mounts" \
        ports:21050,8020 --hostname impala --network "${ctx_network["network_id"]}"

    defer_ret build_run_ctx_reset ctx:ctx_impala

    build_run_container ctx:ctx_impala /wait-for-it.sh -h localhost -p 21050 -t 300

    build_run_ctx_persist ctx:ctx_impala
  }

#   build_stage "Re-tag docker images"
#   {
#     collected_keys=()
#     for key in "${!E[@]}"; do
#         if [[ "$key" == docker_img_* ]] && [[ "$key" != *_tag ]] \
#             && [[ "$key" != *_name ]] && [[ "$key" != *_ref ]] \
#             && [[ "$key" != *_repo ]]; then
#         collected_keys+=("${key}")
#         fi
#     done
#     echo "" > "build-env/gpf-staging-internal-images.yaml"

#     BUILD_NUMBER="$(ee_metadata build_no)"
#     for key in "${collected_keys[@]}"; do
#        image_ref=${E[$key]}
#        image_name=${E[${key}_name]}
#        image_repo=${E[${key}_repo]}
#        image_staging_ref=${image_repo}/${image_name}:staging-$BUILD_NUMBER
#        echo "$image_name:" >> "build-env/gpf-staging-internal-images.yaml"
#        echo "  source: $image_ref" >> "build-env/gpf-staging-internal-images.yaml"
#        echo "  stage: $image_staging_ref" >> "build-env/gpf-staging-internal-images.yaml"

#        build_run_local docker pull ${image_ref}
#        build_run_local docker image tag ${image_ref} ${image_staging_ref}
#        build_run_local docker image push ${image_staging_ref}
#     done
#   }

#   build_stage "Destroy previous staging on dory.seqpipe.org"
#   {
#     local image_ref
#     image_ref="$(e docker_img_iossifovlab_infra)"
#     build_run_ctx_init "container" "$image_ref"
#     defer_ret build_run_ctx_reset

#     build_run bash -c 'cd playbooks/seqpipe-internal; \
#         ansible-playbook \
#             --vault-password-file <(cat <<<"'"$ANSIBLE_VAULT_SEQPIPE"'") \
#             -i seqpipe-internal seqpipe-internal-destroy.yml'

#   }


#   build_stage "Deploy gpf on dory.seqpipe.org"
#   {
#     local image_ref
#     image_ref="$(e docker_img_iossifovlab_infra)"
#     build_run_ctx_init "container" "$image_ref"
#     defer_ret build_run_ctx_reset

#     build_run bash -c 'cd playbooks/seqpipe-internal; \
#         ansible-playbook \
#             --vault-password-file <(cat <<<"'"$ANSIBLE_VAULT_SEQPIPE"'") \
#             -i seqpipe-internal seqpipe-internal-deploy.yml'

#   }

#   build_stage "Deploy federation on dory.seqpipe.org"
#   {
#     local image_ref
#     image_ref="$(e docker_img_iossifovlab_infra)"
#     build_run_ctx_init "container" "$image_ref"
#     defer_ret build_run_ctx_reset

#     build_run bash -c 'cd playbooks/seqpipe-internal; \
#         ansible-playbook \
#             --vault-password-file <(cat <<<"'"$ANSIBLE_VAULT_SEQPIPE"'") \
#             -i seqpipe-internal seqpipe-federation-deploy.yml'

#   }

#   build_stage "Clean up images on dory.seqpipe.org"
#   {
#     local image_ref
#     image_ref="$(e docker_img_iossifovlab_infra)"
#     build_run_ctx_init "container" "$image_ref"
#     defer_ret build_run_ctx_reset

#     build_run bash -c 'cd playbooks/seqpipe-internal; \
#         ansible-playbook \
#             --vault-password-file <(cat <<<"'"$ANSIBLE_VAULT_SEQPIPE"'") \
#             -i seqpipe-internal seqpipe-internal-cleanup.yml'
#   }

#   build_stage "Draw dependencies"
#   {

#     build_deps_graph_write_image 'build-env/dependency-graph.svg'

#   }

#   build_stage "Run GPF import workflow"
#   {
#     build_run_local mkdir -p modules
#     build_run_local cd modules

#     build_run_local bash -e -x <<'EOF'
#         if ! [ -d "gpf_import_workflow_testing" ]; then
#             git clone git@github.com:seqpipe/gpf_import_workflow_testing.git
#             cd gpf_import_workflow_testing
#             git submodule update --init
#             cd -
#         fi
#         cd gpf_import_workflow_testing
#         git checkout master
#         git pull --ff-only
#         git submodule update

#         rm -rf build-env/*

#         find ../../build-env \
#             -iname "*.combined-input.build-env.sh" -print0 | \
#             xargs -0 cp -t build-env/    
# EOF

#     build_run_local cd gpf_import_workflow_testing
#     build_run_local ./build.sh preset:"$preset" clobber:allow_if_matching_values build_no:"$build_no" expose_ports:no generate_jenkins_init:no
#   }


#   build_stage "Run GPF smoke tests"
#   {
#     build_run_local mkdir -p modules
#     build_run_local cd modules

#     build_run_local bash -e -x <<'EOF'
#         if ! [ -d "gpf_smoke_tests" ]; then
#             git clone git@github.com:iossifovlab/gpf_smoke_tests.git
#             cd gpf_smoke_tests
#             git submodule update --init
#             cd -
#         fi
#         cd gpf_smoke_tests
#         git checkout master
#         git pull --ff-only
#         git submodule update

#         rm -rf build-env/*

#         find ../../build-env \
#             -iname "*.combined-input.build-env.sh" -print0 | \
#             xargs -0 cp -t build-env/    
# EOF

#     build_run_local cd gpf_smoke_tests
#     build_run_local ./build.sh preset:"$preset" clobber:allow_if_matching_values build_no:"$build_no" expose_ports:no generate_jenkins_init:no

#     build_run_local  bash -e -x <<'EOF'

#         cd test-results
#         head -1 results.xml | grep -e 'failures="0"' | grep -e 'errors="0"'
#         exit $?

# EOF

#   }

}

main "$@"
