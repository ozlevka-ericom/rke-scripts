#!/bin/bash

set -xe

RKE_VERSION="v0.1.13"
RKE_DOWNLOAD_URL="https://github.com/rancher/rke/releases/download/$RKE_VERSION/rke_linux-amd64"
DOCKER_VERSION="18.03"
DOCKER_SCRIPT_URL="https://releases.rancher.com/install-docker/$DOCKER_VERSION.sh"

function install_docker() {

    if [ ! -x /usr/bin/docker ] || [ "$(docker version | grep -c $DOCKER_VERSION)" -le 1 ]; then
        echo "***************     Installing docker-engine: $DOCKER_VERSION"
        curl -LJ --progress-bar $DOCKER_SCRIPT_URL | sh
    else
        echo " ******* docker-engine $DOCKER_VERSION is already installed"
    fi
}

function install_deps() {
    export LC_ALL=C
    if [ "$(pip3 freeze | grep -c PyYAML)" -lt 1 ]; then
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
        echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list
        apt-get update && apt-get install -y python3-pip apt-transport-https kubectl
        pip3 install PyYaml
    fi
}


#Check if we are root
if ((EUID != 0)); then
    #    sudo su
    echo " Please run it as Root"
    echo "sudo $0 $@"
    exit
fi
CURRENT_USERNAME=$SUDO_USER

apt-get install -y python3-pip

install_docker
usermod -aG docker $CURRENT_USERNAME
install_deps


RETURN_CODE=$(curl -LJ --progress-bar -w '%{response_code}' -o ./rke  "$RKE_DOWNLOAD_URL")
if [ "$RETURN_CODE" != "200" ]; then
    echo "Error: Cannot download rke "
    exit 1
fi

chmod +x ./rke
mkdir -p "/home/$CURRENT_USERNAME/.ssh"
mkdir -p /root/.ssh

chown $CURRENT_USERNAME:$CURRENT_USERNAME "/home/$CURRENT_USERNAME/.ssh"

ssh-keygen -t rsa -f rsa_key -q -N "" -C "$CURRENT_USERNAME"

tee -a ./prepare-yml.py << EOF
import yaml
import os
import argparse


current_dir = os.getcwd()

def prepare_yaml():
    with open('./cluster.yml', mode='r') as file:
        config = yaml.load(file)

    config['nodes'][0]['ssh_key_path'] = current_dir + '/rsa_key'

    with open('./cluster.yml', mode='w') as file:
        yaml.dump(config, file)

def install_key(user):
    with open(os.path.join(current_dir, "rsa_key.pub"), mode='r') as file:
        key = file.read()

    with open(os.path.join("/home", user, ".ssh/authorized_keys"), mode='a') as file:
        file.write(key)

    with open("/root/.ssh/authorized_keys", mode='a') as file:
        file.write(key)



def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", default="key", help="Check what operation")
    parser.add_argument("--user", required=False, help="Username to install key for")

    args = parser.parse_args()

    if args.operation == "key":
        install_key(args.user)
    else:
        prepare_yaml()



if __name__ == "__main__":
    main()
EOF

tee -a ./cluster.yml << EOF
nodes:
  - address: localhost # hostname or IP to access nodes
    user: ericom # root user (usually 'root')
    role: [controlplane,etcd,worker] # K8s roles for node
    ssh_key_path: /home/ericom/.ssh/id_rsa # path to PEM file

services:
  etcd:
    snapshot: true
    creation: 6h
    retention: 24h

ignore_docker_version: true

addons: |-
  ---
  kind: Namespace
  apiVersion: v1
  metadata:
    name: cattle-system
  ---
  kind: ServiceAccount
  apiVersion: v1
  metadata:
    name: cattle-admin
    namespace: cattle-system
  ---
  kind: ClusterRoleBinding
  apiVersion: rbac.authorization.k8s.io/v1
  metadata:
    name: cattle-crb
    namespace: cattle-system
  subjects:
  - kind: ServiceAccount
    name: cattle-admin
    namespace: cattle-system
  roleRef:
    kind: ClusterRole
    name: cluster-admin
    apiGroup: rbac.authorization.k8s.io
  ---
  apiVersion: v1
  kind: Secret
  metadata:
    name: cattle-keys-ingress
    namespace: cattle-system
  type: Opaque
  data:
    tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUZORENDQXh5Z0F3SUJBZ0lDRUFBd0RRWUpLb1pJaHZjTkFRRUxCUUF3VURFTE1Ba0dBMVVFQmhNQ1NVd3gKRHpBTkJnTlZCQWdNQmtsemNtRmxiREVZTUJZR0ExVUVDZ3dQUlhKcFkyOXRJRk52Wm5SM1lYSmxNUll3RkFZRApWUVFEREExeVlXNWphR1Z5TG14dlkyRnNNQjRYRFRFNE1USXhOakE1TkRrME0xb1hEVEU1TVRJeU5qQTVORGswCk0xb3dVREVMTUFrR0ExVUVCaE1DU1V3eER6QU5CZ05WQkFnTUJrbHpjbUZsYkRFWU1CWUdBMVVFQ2d3UFJYSnAKWTI5dElGTnZablIzWVhKbE1SWXdGQVlEVlFRRERBMXlZVzVqYUdWeUxteHZZMkZzTUlJQklqQU5CZ2txaGtpRwo5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBdFBodkV5VTUxblc1VWJPSnpjZjAwMUxIL3kvQkF2Nm0xY0NzClYvVHJNSDlCQWlVbldzem0yNWZNQjYrQlFGVVJuTEZzeSt3dklBWVZRMVQ1dDl4ZURsZHVWdndyNnFoNTFZMDUKM21vY2N1eW5iWWErZVBzT09kU05FZlFWV3FrY1lNVEh6TnJIM0Q1UDI5ZHlmdHUwbkJUNng3bWlvYWdGbWZHaQpJbXk1QzA2NERBUmtSUnlmeHpwdk1DVDVEREIyTXErSTZpQ2hKZFYzRnVIbXduc0VyTS9mQXNUM1VaMUFwSjk2CnI3dFJyZWlKQmhZbE9NeEpwbzN3YUdtcmlTbWR1WmhMTUxKcmtjcld1THpJL0wzRHNuYUdkYS9ybnpZdDVWalYKQzNsVlBLanJybVFvNzVPK1daOXI5amhFVXNkbE5ZUG1MMnVTcFdqL3BVTkdDVmpDMFFJREFRQUJvNElCRmpDQwpBUkl3Q1FZRFZSMFRCQUl3QURBUkJnbGdoa2dCaHZoQ0FRRUVCQU1DQmtBd013WUpZSVpJQVliNFFnRU5CQ1lXCkpFOXdaVzVUVTB3Z1IyVnVaWEpoZEdWa0lGTmxjblpsY2lCRFpYSjBhV1pwWTJGMFpUQWRCZ05WSFE0RUZnUVUKdFFveFJPTE4zeUtPa1puMEVJdHluRHJVeVJrd2VRWURWUjBqQkhJd2NJQVVRZGk5ZGJsYWgrcmNudGkxYTd5TwpweFptQlY2aFZLUlNNRkF4Q3pBSkJnTlZCQVlUQWtsTU1ROHdEUVlEVlFRSURBWkpjM0poWld3eEdEQVdCZ05WCkJBb01EMFZ5YVdOdmJTQlRiMlowZDJGeVpURVdNQlFHQTFVRUF3d05jbUZ1WTJobGNpNXNiMk5oYklJQ0VBQXcKRGdZRFZSMFBBUUgvQkFRREFnV2dNQk1HQTFVZEpRUU1NQW9HQ0NzR0FRVUZCd01CTUEwR0NTcUdTSWIzRFFFQgpDd1VBQTRJQ0FRQ0pnc2xhMVJ1VlBNSHkvY0gxalhJOGtnT1ZHOUFPcEN1VERlZUd1ZktpRDh2TldHT29NM0xYCmZrVlUrVWEyUEllV2Q4ekxKMk0xd1hVa0ZSVWM2czVHK2NRVEtMa3BqNXVITGY5alZOZ2NvVDdrMDljdVh6MW0Kc2NIM2pBK1kvSkNsOXR1R3h1L1VyRmw1OGlRYUxPQkpwOVBOOVdNYytrV1pMYWhYazhSR2xBUkFTZzdZUmhyUwpBZEYxMm15bE9MRnNyWFFDZjJrWmx6SGxXaTZCU2MzamJjZHFUOFEyWGFuUWl1REttRTdCQ2VRbDFwRCtKZTJmClFDT0ZMa2ZEeFVJZnl5RW01MVRPdUR6cHV3N0lMWlNJZnJvNkZpWlBhc3lpMkFDNHV3M0JML3FzM0RtU3JLeW0KL1hPSWlJcVJCTjF4MEdPL2xodGlmTG5rUWZEaERkYU9ZMmdpZHBxc0IxMFFJcy9VNzd5bUVkdmVWd3BrdXMxWAo4K1FLcVA1aW5xZnZtM0RzY3duQjBnV280ZHM3MzVxM0hDT2VnaHVvYkZwbFlMd2xMZCtwdWtJUFd3MDE5bXZVCk8zOVdKc014VnNjNjdwdkplR0ZFWUQ1d1FNYVAvalRwdkczZzc3Q01WVXZ3ZEo5S2tFVncySU1KREJJWk5NL3kKdWRSaTk0UDVxNGwyYyt1STNVQXRDajBJeW9XRzQ1anVXRy8wckxLNnRDSDFHeGlLRjdJTjJiaTd3YXJkUlBrYQp0RTNqSytiQy9BbmVqMVM5QWF4a2pabFdnS1g2MUp3T3g1ckNiaUlYMjNkNm5jQmIwMnNsZ2ZYTnVsb3doeWhLCkkyQS95TWh1ckl3Y05kZnpFYndxYTBSSXAzQlJaWHBidmRxUWFWSWh5QmZ4bG16ZlpUb2pRQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0KLS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUZnakNDQTJxZ0F3SUJBZ0lDRUFBd0RRWUpLb1pJaHZjTkFRRUxCUUF3VURFTE1Ba0dBMVVFQmhNQ1NVd3gKRHpBTkJnTlZCQWdNQmtsemNtRmxiREVZTUJZR0ExVUVDZ3dQUlhKcFkyOXRJRk52Wm5SM1lYSmxNUll3RkFZRApWUVFEREExeVlXNWphR1Z5TG14dlkyRnNNQjRYRFRFNE1USXhOakE1TkRreE1Gb1hEVEk0TVRJeE16QTVORGt4Ck1Gb3dVREVMTUFrR0ExVUVCaE1DU1V3eER6QU5CZ05WQkFnTUJrbHpjbUZsYkRFWU1CWUdBMVVFQ2d3UFJYSnAKWTI5dElGTnZablIzWVhKbE1SWXdGQVlEVlFRRERBMXlZVzVqYUdWeUxteHZZMkZzTUlJQ0lqQU5CZ2txaGtpRwo5dzBCQVFFRkFBT0NBZzhBTUlJQ0NnS0NBZ0VBbnlYOXFTaUhCSEFGeDdXMXZKV1dMMklhL0hVZzluVXhlV2FQCkdCRUNCYXRPZ2RuMDlweTZwUXZPZy9HRlFXMnZjek9vOWxiTUtqajBjNldTRXRsc2lOR0Iyd3VHT25OcjVJWHUKRC85a0JPUXBRRlFKWGkrbWFZK2VsK3IyYk9nK0tsbW9ZaUtFMFcwRDVlQlN6NGpWdVBLd1QxcWhvUWFHa2hybgpLYzFBeXQ3K2dtWjUwdStLRkg3eVMrcmtuaUppQmQ0SkpXMnBORDNWbGVSSGx1RDZTWHRmbTltazBmQ20veHcvClViZVBZWXJNTFhneHFkdjNpd0lZaHpzN2VTSEY3MGJaZDlNM2dBSkt3VkdQZUg0eHkwRHoraDg2T0RMRlZLZzcKcFI0RkZ0b21HaXZDaVlmRnhiaGE1NDB6OXJhcjZ2M01xUjR4cVl6T3F0ZVY5OXZNZXBWS3RPWkw4UkpibzNkVQp4MHJGNW5DRU1UK3BoeG9PbFRPbTRJYmExMGZOTDVjSkh0cFIwMU9TQ21uNFFoUWpUTit1N2JzQzRMS0Nkbng1CnFMSzRydi9zSnlzWE0rbCtQVjJXeXg4a1ZKdHZJamtlV1VjWnVaTmZReC9VTnlxeVU1K2pRSXRsUDZoRUJMdnUKaC9tZHU1eVg3S0dGOW5Ld1dkLzhUbjdQRzZIWHNGQkFLRm9PclB2blZZS1U0STRtangrM2VMS0M4ZDNuK01JbwpaQXZPY2gvNHpGVUE1UHJaK3Z2UUNIRmNwczFqTGk3eHVGb3NhYnlDZ3hQbjA1T3N0bXRsRGV1ZFBNdGtxSGF0ClczOWJ6QnN5MGgrc2pzRjVCeWpQMGNnazBmcW1zZTgrOHlhdjFUT3Zac3pJa1JncXJReGc4bFBhL3ZaTFpUZFcKdlNSUjA2TUNBd0VBQWFObU1HUXdIUVlEVlIwT0JCWUVGRUhZdlhXNVdvZnEzSjdZdFd1OGpxY1daZ1ZlTUI4RwpBMVVkSXdRWU1CYUFGQXIvRWcva1ViaDl3ZDgvZWFwQWJsV3dsQ2hiTUJJR0ExVWRFd0VCL3dRSU1BWUJBZjhDCkFRQXdEZ1lEVlIwUEFRSC9CQVFEQWdHR01BMEdDU3FHU0liM0RRRUJDd1VBQTRJQ0FRQ1NWa1lWbkdscmdxdkQKMFNZWXRERndzTlYxREE3NUlVQk03QjRHelN1MUhEclpyakZkQWRFd3BoaC9EbElEZW8vUnZveGsyYTJxTUFZQQpVaE4wcnpITTk2ZWZzU2ZnWHZVZXVpb1dMUGpWSnZTcFBmalZheGFyTkdpbmgxb2lWNWhIMWxRM0xoVGhUQVdtCjVCWVkyK2YvRGo5cmVlOWh1TTZBdXNjZG5mRm1NRHpaYVc2bFdJdjJYR1N2cDZ6UEg2MUZ1L0lxRnVaSTRTMWMKOXQ5ZTB2Q0tvcFpjMUdLWE9WdGdMR3YwaTJkQWtDTzVQOXdhdFE3bXRLOGpXNm1TRlVpcExVNG5hYWd0NHN6UgppTG1zNnVpUmxCQ3RWUXl4ZUh6S3I0TUpoOWhVY09VWFpVbGJuQmplMDQrUDJUYWFOczBWckdJdTFHUEFkcDVKCitEd2lpQy83ZktSTDBJZngzMlNUNEJYN1NDVWUydnRlSmoyTW0rOXo0cGEwQjB2UU9GbVpNbE9uaEx4ZkNrdDIKdERUN0ZaQzB1dElmakFaSDd4WkFQODRWQnJMeDhTU2hEcXpRU0tkd2xpVjkwM0dYZnJ4em04ZmRYM3IvTE1sRApXdzNEc3NkaGtxcEVTaExGRFNacVpMSzlOYWhkVlpNZW5Na29TNTBhd2R1NUVwbnhQYTMyWFhUdmZaMGVVcThzCkhJVnVKaFFIV3I4TlZiTHROcnhCcGVYVWZud3NQSnZzSFNzNkpvQTNEYUJsODdFT21pZm5sTlQ0YXR4RUFxUkkKOTVjWjQ0OUlxa0lpWmIwMjVxbjFqUEw2YXhRbDc5ZzdaZ1VaTG55Kzdtd3hPUXUwaCtlWjJUYTBxMlVYbUJLTwpaY3VFRGpqK2MvVVgxWDhTWDh1T2szMjFtNERobVE9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    # ssl cert for ingress. If selfsigned, must be signed by same CA as cattle server
    tls.key: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFcEFJQkFBS0NBUUVBdFBodkV5VTUxblc1VWJPSnpjZjAwMUxIL3kvQkF2Nm0xY0NzVi9Uck1IOUJBaVVuCldzem0yNWZNQjYrQlFGVVJuTEZzeSt3dklBWVZRMVQ1dDl4ZURsZHVWdndyNnFoNTFZMDUzbW9jY3V5bmJZYSsKZVBzT09kU05FZlFWV3FrY1lNVEh6TnJIM0Q1UDI5ZHlmdHUwbkJUNng3bWlvYWdGbWZHaUlteTVDMDY0REFSawpSUnlmeHpwdk1DVDVEREIyTXErSTZpQ2hKZFYzRnVIbXduc0VyTS9mQXNUM1VaMUFwSjk2cjd0UnJlaUpCaFlsCk9NeEpwbzN3YUdtcmlTbWR1WmhMTUxKcmtjcld1THpJL0wzRHNuYUdkYS9ybnpZdDVWalZDM2xWUEtqcnJtUW8KNzVPK1daOXI5amhFVXNkbE5ZUG1MMnVTcFdqL3BVTkdDVmpDMFFJREFRQUJBb0lCQVFDR2dWZmRQUC9kL0NXLwpLZGcwa0hmUlVXZkFyWGVoaUMvc0U0YUU0VTZrL3hBTVRoMFFDZGRVUTJDc0hhL05adXp1TDVrVGYvb09yVGJFCmtyWUFCOVFJaU1kRDg2MllmWndBTXpWZHNEUnczcUFhY2RuRUJhVXZLbUduaEdrU3R6cVdXZXUrd0tWbmR4RFgKN3l2MFNjdlZibXB1WS9VU2ZkV2I4OUowRDZjQlZVSndMQ3J3WStrbnNqREQyU0V6NmQxS2t0blhQVnEzWVQrYgpDWE9XVXpHeEV4dXZzQ1JWSk1hNUNjTkhNZEZJQk43ZDAzT1NtT0RjWkNrRStHV2RIaXBXNTVpVCtOcTlORGY2CjVMUkNzUktFOUdaOHBMSlZpUjdWaXZhT2tCK2dZbWFJZFNXUzlQazF1WnMrazk2dU1XcTlubERkbjB3MHQydlcKQy81L0VGYzVBb0dCQU9JdkY1SWlHL0lkSVFnRlEzL3FMRS9hZlJ5TWY3UWhROFZCbnhNRmlqSkJzTFZtZytLUwo4K01vemJ3WjJIcldwaUxnbm5aenJJbFZqK3BjSCsxK0FYUXlTZHFmOUs0ZFM4VEVhZFJ5eWF5aDhuVkZ6WEZJCm9IRnd4NmdMeTdaTUh4L2l1TXAxTUFQS21Id0RyMytmSldOVUlKVUFNVndZVVVGb2xtUy9IMEV6QW9HQkFNelQKaThFelJQNDBCODRLVVZFMHRjTHl5M2JLMkJhN255VFFQZHpQZFJMWndoKy9KdnROQ2xJeUZLMlZlR3ZqNzJDQwpPaUhndHFuSXd3eG12V280S3IyRlBHMGV1QUg2S1lDNTJNR3dYV2ZsT2RtKzNMWnQ4WklLQ1luem9QbVRMWURGCjBQMEo4Q0ExYjVwRkRUNnBwWTRpNDF5a1drdE0xdjNFK1l1NUtuUHJBb0dCQUwzcFVuNDF1NGN2cEJOcThBRVEKSzBLbExsVnhOcXlWSGFVYmN5aHloMVdwU0drWGVYY2Rjai95ZThRTFkzUElsTmhHQjJkbnVwL1pRcXhCeStFSgo0c2lnak5oUFpBOXBzN3UwT3pQUmFicFVoQktwbUZVYzZQSTNBcno3b29FZkt5Y0hvNmNDZkYxQ2w0UFJTR0w4CnlsUzdSMXcwUEQyYWdXZE5ITEhjczY1M0FvR0FKRU56NDlIQzdrcWg4eDJxaGZrU0VTRFJXd2ZRdUQyaGtHLzUKOCtVYThpcHhqeE5Wd0hwRVVJY2pXQlExak14L0xoUUFYTTBmS2ZJc2JqNm1YRzd6U2ppVG1USXVHOU9CazVQVAp4MzhGR29iZjlpZ3ZoWER6cXdweDQrV3BZMlptVVAwMDRnZm5acHh2Vk4zUzJYeEpubCtZNTJjRndYMHFOeVd2CmxNaEV0dDhDZ1lCeVNLQ2Y3TUwvTSs2cjBKVWZsVjFTdytpdm5rN0RUYVlHY3ByRTNwK3NPQzRlVnJIalVKekEKckgzWFl1WVNSVFVhU2tBV2kvY3dnUzZRZUlGcFREZ2IwT0lucUFpc2RlQXRlV3pSbGdTRjFHTCtqa21HTTZXRwpSRnJsTUNmSjFFbGlLVHRWRjJkRXRuS3FKcXUzbk91d1VFU1RnTUgxS3czNFVOdUR1RGEyamc9PQotLS0tLUVORCBSU0EgUFJJVkFURSBLRVktLS0tLQo=
    # ssl key for ingress. If selfsigned, must be signed by same CA as cattle server
  ---
  apiVersion: v1
  kind: Secret
  metadata:
    name: cattle-keys-server
    namespace: cattle-system
  type: Opaque
  data:
    cacerts.pem: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUZoakNDQTI2Z0F3SUJBZ0lKQUxiS2FIa3ZXSnQ1TUEwR0NTcUdTSWIzRFFFQkN3VUFNRkF4Q3pBSkJnTlYKQkFZVEFrbE1NUTh3RFFZRFZRUUlEQVpKYzNKaFpXd3hHREFXQmdOVkJBb01EMFZ5YVdOdmJTQlRiMlowZDJGeQpaVEVXTUJRR0ExVUVBd3dOY21GdVkyaGxjaTVzYjJOaGJEQWVGdzB4T0RFeU1UWXdPVFE0TkROYUZ3MHpPREV5Ck1URXdPVFE0TkROYU1GQXhDekFKQmdOVkJBWVRBa2xNTVE4d0RRWURWUVFJREFaSmMzSmhaV3d4R0RBV0JnTlYKQkFvTUQwVnlhV052YlNCVGIyWjBkMkZ5WlRFV01CUUdBMVVFQXd3TmNtRnVZMmhsY2k1c2IyTmhiRENDQWlJdwpEUVlKS29aSWh2Y05BUUVCQlFBRGdnSVBBRENDQWdvQ2dnSUJBTElybWJ2KzVBZEpYRmtlTTdBRnRuOXhwZXNXCkw3TEY4aWc2LzluKzBaSWlCeHJ5RU82d295ei82cnl0WVFIaWJPcGtNdzI2RnlYWi9mUCs1b2NyZktJMldNRUkKVFJUY1BObzMrK05jQmppS1RCRlhER0hqTFlkVzluVHY3OElQYloyZW85UG5PdlAyR2Ftd2I2akxJK3RwRjNvSQpXU1FXbkl0akdRcHBBZHNOMFlFQmQ3TVNQemNjOFJtQllEYjRjUTl6V0haU1lpT3N2amNHNVdHb2dZVzU0eENGCmFzWG9sYklCOXQxdDNpUTZVUWJ3QThkTCtZRVhiNlJucFhuUU04NEdaYXJLNFQ1czZBeE1tNE9qM0ZiTldxbXcKUmhFS3IwRFZZdWRPZHlrSklXbnhSOFYrSm9NTzdkeXFUbU1FeDZ1US8xZ2VpTU93clhpTXp4TXp0aVJ5TU1kcgplWnlaWTdHY09ZQnU1bFljWTlldExZZ3Q3NytwUmlFNElWYXRTbktuWFJEQnJDQWcrVGJoUjJWQlNuTGtPNWsxCmZnZlZLZk1STkc4RHRmdjNjVHo1eGViSFJwa2FzN29Bc2RacGF4RGpUL1Zzdk1DcUpYQlB6R2FHZ1BYWTRodWEKOVRTQ2MvTVppY1ZCY2d4U2dHQUd3UEp6V1AwTzZySW4wREI2M2hERFg3KzgxVTZvQ25Zemo2aS9RTXhqVE8xYQo4MXVTSkxpRzJqODA0UVhpWTdPbkFrNTNWdVBxTWcxU2s2RE1BNjJDNHBYODBodnpQWlFaQTdUZVBNeGd3WkVFCjh4UitFdHRRaUp0VkdWK21tZnE4TTJOY3RnYVpubWs5cnRiME1BRjhBRE5qWHk2TFZUMkdsS1VHckwwdFEwQzEKWUMrVWtnbzVtdmJMSEp1cEFnTUJBQUdqWXpCaE1CMEdBMVVkRGdRV0JCUUsveElQNUZHNGZjSGZQM21xUUc1VgpzSlFvV3pBZkJnTlZIU01FR0RBV2dCUUsveElQNUZHNGZjSGZQM21xUUc1VnNKUW9XekFQQmdOVkhSTUJBZjhFCkJUQURBUUgvTUE0R0ExVWREd0VCL3dRRUF3SUJoakFOQmdrcWhraUc5dzBCQVFzRkFBT0NBZ0VBbGZ0Z2hiemkKeEZiWmgyV0U1NlI3ZGVUMU9hQ0JnVG5TbWhPN3h5T0FkTGxMN0pNdGNFaVRYYzY1UUVwK3ZsOWRGbWorNW1ycAp5ZzhPNW1NNzAxeFdwL0VOeW1qTVh2MExxNjVJNUU1WWREQ3pvSkM3aUZFbGh1aFREcjFnRFk0eUw4QWE4WTd4CldUdHJBWnhZNGNBTUw5RkZXbUhWbEwvTGZVMlBBZ1ZRUmE3dEFaWlRVTzVManl3R3lobWFNUVZwb0ZQSmxMMGwKejBhanV3RU1wdzZ2VVFGTWtwMWlrWkdpVm1pbWxjZTFibUE2WmpSWDBkbHFJTzRidkhjQlRVU2pmVDJCMmcrNQpEcld2TkVDNG1iSktJb25jQzVqVXNnUGtJSUlyNXhNVnNmSTEzUzZSLzlWb3pHSFp0SjBuY3Rhck9SSmwrVmtCCkM4bHFEb0VHQjQ4RVZtZUdXL0lkZG5xdnNTREcrc2MrRTFLdDVqeXBzRU5tR0M5bjZTdDZhOE1WOXdvQVJqSmUKbEJBSWtxVHZaNGxjZW1TVzZ2QjVsVXJpeWpEbnZxcHRlYTJnT2tSYzJaeWs1Y0J5QjduYWVQcDJrSi9scWtLeApCaWZrZGIzT1dySlpVNXJ5UUhITnJDaXE2emxGaTFKclRKTFE1SjNJM2tBbVhNOWN3VVRPWVdhL0ZSbVNzNjZRCkx0UC96M1pWdkFPZnN3c0RaWHhHZWp2aTlqVmkvQmdXK05PRitjUzlsR01uRnJyd0VVOGdxYVgzYXlUb0dZYWUKcTFiUUdHT3VEdUdUQXRkTm1yZ0lXYloyMjBpZkxiYVNQakJkSkdBaDlJdXZ2ZGdpbG5vbERuU1EyTlZhNnhVbgp2SkI3V3l1TytwbXp6YzRjYUc3L2w2aUZ0L1QraEpJem9rbz0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
    # CA cert used to sign cattle server cert and key
  ---
  apiVersion: v1
  kind: Service
  metadata:
    namespace: cattle-system
    name: cattle-service
    labels:
      app: cattle
  spec:
    ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
    - port: 443
      targetPort: 443
      protocol: TCP
      name: https
    selector:
      app: cattle
  ---
  apiVersion: extensions/v1beta1
  kind: Ingress
  metadata:
    namespace: cattle-system
    name: cattle-ingress-http
    annotations:
      nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "1800"   # Max time in seconds for ws to remain shell window open
      nginx.ingress.kubernetes.io/proxy-send-timeout: "1800"   # Max time in seconds for ws to remain shell window open
  spec:
    rules:
    - host: rancher.local # FQDN to access cattle server
      http:
        paths:
        - backend:
            serviceName: cattle-service
            servicePort: 80
    tls:
    - secretName: cattle-keys-ingress
      hosts:
      - rancher.local  # FQDN to access cattle server
  ---
  kind: Deployment
  apiVersion: extensions/v1beta1
  metadata:
    namespace: cattle-system
    name: cattle
  spec:
    replicas: 1
    template:
      metadata:
        labels:
          app: cattle
      spec:
        serviceAccountName: cattle-admin
        containers:
        # Rancher install via RKE addons is only supported up to v2.0.8
        - image: rancher/rancher:v2.0.8
          imagePullPolicy: Always
          name: cattle-server
  #       env:
  #       - name: HTTP_PROXY
  #         value: "http://your_proxy_address:port"
  #       - name: HTTPS_PROXY
  #         value: "http://your_proxy_address:port"
  #       - name: NO_PROXY
  #         value: "localhost,127.0.0.1,0.0.0.0,10.43.0.0/16,your_network_ranges_that_dont_need_proxy_to_access"
          livenessProbe:
            httpGet:
              path: /ping
              port: 80
            initialDelaySeconds: 60
            periodSeconds: 60
          readinessProbe:
            httpGet:
              path: /ping
              port: 80
            initialDelaySeconds: 20
            periodSeconds: 10
          ports:
          - containerPort: 80
            protocol: TCP
          - containerPort: 443
            protocol: TCP
          volumeMounts:
          - mountPath: /etc/rancher/ssl
            name: cattle-keys-volume
            readOnly: true
        volumes:
        - name: cattle-keys-volume
          secret:
            defaultMode: 420
            secretName: cattle-keys-server
  ---
  kind: ConfigMap
  apiVersion: v1
  metadata:
    name: tcp-services
    namespace: ingress-nginx
  data:
    "4444": cattle-system/cattle-service:443
EOF

python3 prepare-yml.py key --user "$CURRENT_USERNAME"
python3 prepare-yml.py notkey

./rke up




