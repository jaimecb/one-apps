# frozen_string_literal: true

# ---------------------------------------------------------------------------- #
# Copyright 2025, OpenNebula Project, OpenNebula Systems                       #
#                                                                              #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
# ---------------------------------------------------------------------------- #

begin
    require '/etc/one-appliance/lib/helpers'
rescue LoadError
    require_relative '../lib/helpers'
end

require_relative 'config'

module Service

    module KaaS

        extend self

        DEPENDS_ON = []

        def install
            msg :info, 'KaaS::install'

            msg :info, "Download Clusterctl: #{KAAS_CLUSTERCTL_VERSION}"
            clusterctl_url = 'https://github.com/kubernetes-sigs/cluster-api/releases/download/' \
                            "v#{KAAS_CLUSTERCTL_VERSION}/clusterctl-linux-amd64"
            bash <<~SCRIPT
                curl -fsSL #{clusterctl_url} \
                | install -o 0 -g 0 -m u=rwx,go= -D /dev/fd/0 '/usr/local/bin/clusterctl'
            SCRIPT

            msg :info, "Download Helm: #{KAAS_HELM_VERSION}"
            bash <<~SCRIPT
                curl -fsSL 'https://get.helm.sh/helm-v#{KAAS_HELM_VERSION}-linux-amd64.tar.gz' \
                | tar -xzO -f- linux-amd64/helm \
                | install -o 0 -g 0 -m u=rwx,go= -D /dev/fd/0 '/usr/local/bin/helm'
            SCRIPT

            msg :info, "Download Kind: #{KAAS_KIND_VERSION}"
            kind_url = 'https://github.com/kubernetes-sigs/kind/releases/download/' \
                        "v#{KAAS_KIND_VERSION}/kind-linux-amd64"
            bash <<~SCRIPT
                curl -fsSL #{kind_url} \
                | install -o 0 -g 0 -m u=rwx,go= -D /dev/fd/0 '/usr/local/bin/kind'
            SCRIPT

            msg :info, "Download Kubectl: #{KAAS_KUBECTL_VERSION}"
            bash <<~SCRIPT
                curl -fsSL 'https://dl.k8s.io/release/v#{KAAS_KUBECTL_VERSION}/bin/linux/amd64/kubectl' \
                | install -o 0 -g 0 -m u=rwx,go= -D /dev/fd/0 '/usr/local/bin/kubectl'
            SCRIPT

            msg :info, 'Create management cluster with Kind'
            bash <<~SCRIPT
                kind create cluster
                kind get kubeconfig > #{KAAS_MGMT_KUBECONFIG_PATH}
            SCRIPT

            msg :info, 'Initialize management cluster'
            bash <<~SCRIPT
                clusterctl init \
                --bootstrap=rke2 \
                --control-plane=rke2 \
                --infrastructure=opennebula
            SCRIPT

            msg :info, 'Add Capone Helm repo and pull RKE2 chart'
            bash <<~SCRIPT
                helm repo add capone https://opennebula.github.io/cluster-api-provider-opennebula/charts/
                helm repo update capone
                helm pull capone/capone-rke2 --destination #{KAAS_APPLIANCE_PATH}
            SCRIPT
        end

        def configure
            msg :info, 'KaaS::configure'

            msg :info, 'Start Management Cluster'
            bash <<~SCRIPT
                podman start kind-control-plane
            SCRIPT

            msg :info, 'Deploy Workload Cluster'
            begin_retry(12, 10) do
                puts bash <<~SCRIPT
                    helm upgrade --install capone #{KAAS_MGMT_CAPONE_CHART_PATH} \
                    --kubeconfig #{KAAS_MGMT_KUBECONFIG_PATH} \
                    --set ONE_XMLRPC=#{KAAS_ONE_XMLRPC} \
                    --set ONE_AUTH=#{KAAS_ONE_AUTH} \
                    --set CLUSTER_NAME=#{KAAS_CLUSTER_NAME} \
                    --set KUBERNETES_VERSION=#{KAAS_CLUSTER_VERSION} \
                    --set PUBLIC_NETWORK_NAME=#{KAAS_CLUSTER_NETWORK_PUBLIC} \
                    --set PRIVATE_NETWORK_NAME=#{KAAS_CLUSTER_NETWORK_PRIVATE} \
                    --set CONTROL_PLANE_MACHINE_COUNT=#{KAAS_CLUSTER_CP_COUNT} \
                    --set WORKER_MACHINE_COUNT=#{KAAS_CLUSTER_WORKER_COUNT}
                SCRIPT
            end

            msg :info, 'Create backup directory'
            bash <<~SCRIPT
                install -d backup
            SCRIPT

            msg :info, 'Backup Management Cluster'
            begin_retry(60, 10) do
                puts bash <<~SCRIPT
                    clusterctl -v=4 move \
                    --to-directory=backup/ \
                    --kubeconfig #{KAAS_MGMT_KUBECONFIG_PATH}
                SCRIPT
            end

            msg :info, 'Retrieve Workload Cluster Kubeconfig'
            bash <<~SCRIPT
                clusterctl get kubeconfig #{KAAS_CLUSTER_NAME} \
                --kubeconfig #{KAAS_MGMT_KUBECONFIG_PATH} > #{KAAS_WKLD_KUBECONFIG_PATH}
            SCRIPT

            msg :info, 'Initialize CAPI on Workload Cluster'
            bash <<~SCRIPT
                clusterctl init \
                --bootstrap=rke2 \
                --control-plane=rke2 \
                --infrastructure=opennebula \
                --kubeconfig #{KAAS_WKLD_KUBECONFIG_PATH}
            SCRIPT

            msg :info, 'Move CAPI objects to Workload Cluster'
            bash <<~SCRIPT
                export KUBECONFIG=#{KAAS_WKLD_KUBECONFIG_PATH}
                clusterctl -v=4 move \
                --from-directory=backup/
            SCRIPT
        end

        def bootstrap
            msg :info, 'Capi::bootstrap'
        end

    end

    def begin_retry(max_retries, delay)
        max_retries.downto(0).each do |_retry_num|
            yield
            break
        rescue StandardError => e
            puts "Error: #{e.message}"
            sleep delay
        end
    end

end
