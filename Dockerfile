FROM ubuntu:16.04


RUN apt-get update && apt-get install -y \
  curl \
  less \
  ssh  \
  sudo \
  vim 

#RUN ssh-keygen -q -t rsa -f /root/.ssh/id_rsa
#RUN cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys

RUN apt-get install -y  software-properties-common
RUN apt-add-repository ppa:ansible/ansible
RUN apt-get update
RUN apt-get install -y ansible

ENV PATH $PATH:/root/
WORKDIR /root
CMD cd build/damp/ ; ansible-playbook -i hostfile setup.yml --limit localhost ; /bin/bash

