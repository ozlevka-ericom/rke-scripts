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