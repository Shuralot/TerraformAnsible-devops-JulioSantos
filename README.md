# Projeto Final: Provisionamento e Configuração Integrados (Terraform + Ansible)

Este repositório contém a solução do **Projeto Final (Atividade 3)** da disciplina de **Infraestrutura como Código**. O objetivo do projeto é demonstrar a integração automatizada e idempotente de ponta a ponta entre o Terraform (provisionamento) e o Ansible (configuração), implantando a aplicação Docker `getting-started-app` em uma instância EC2 na AWS.

---

## 1. Arquitetura da Solução

O diagrama abaixo detalha a topologia da rede provisionada na AWS e o fluxo de integração entre as ferramentas:

```
Internet
   │
   ▼
[ Internet Gateway ]
   │
   ▼
VPC (Ambiente dev: 10.0.0.0/16 | Ambiente prod: 10.1.0.0/16)
   │
   ▼
Subnet Pública (Ambiente dev: 10.0.1.0/24 | Ambiente prod: 10.1.1.0/24)
   │
   ▼
Security Group (Portas: 22/TCP [SSH], 3000/TCP [Web App])
   │
   ▼
┌──────────────────────────────────────┐
│  Instância EC2 (t3.micro)            │ ◄── Provisionada pelo Terraform
├──────────────────────────────────────┤
│  - Docker Engine                     │ ◄── Instalado pelo Ansible
│  - Container: getting-started-app    │ ◄── Executado pelo Ansible (community.docker)
│    (Porta do host 3000 -> container 80)
└──────────────────────────────────────┘
   ▲
   │ (Fluxo de Execução)
   │
[ terraform apply ] ──► [ local-exec ] ──► [ Gerar hosts.ini ] ──► [ ansible-playbook (WSL) ]
```

---

## 2. Detalhes de Implementação da Integração

A integração segue a **Opção B (local-exec disparando o Ansible automaticamente)**, adaptada para funcionar de forma limpa em ambiente Windows rodando Ansible dentro do WSL (Windows Subsystem for Linux):

1. **Geração da Chave SSH**: O Terraform gera uma chave privada TLS (`tls_private_key.ssh`) dinamicamente e a registra como uma chave de acesso na AWS (`aws_key_pair.ssh`). A chave privada é salva localmente em `terraform/id_rsa.pem`.
2. **Geração do Inventário**: O Terraform grava de forma dinâmica o arquivo `ansible/hosts.ini` contendo o IP público da instância EC2 provisionada.
3. **Orquestração da Execução (`local-exec`)**:
   - Um recurso `null_resource.ansible_trigger` detecta alterações na instância EC2 (ID ou IP).
   - O provisionador `local-exec` utiliza o interpretador PowerShell para executar as seguintes etapas:
     - **Aguardar SSH**: Executa um loop de verificação via socket TCP em PowerShell que monitora o IP na porta `22` até que o servidor esteja aceitando conexões SSH.
     - **Preparar WSL**: Cria o diretório `/home/Shura/.ssh` no WSL e copia a chave SSH (`id_rsa.pem`) e a senha do vault (`vault_pass.txt`) com as permissões corretas (`chmod 600`) para evitar erros de leitura e segurança.
     - **Execução do Playbook**: Dispara o `ansible-playbook` utilizando o executável do Ansible instalado no WSL, passando as referências de inventário, chave privada e arquivo de senha do Ansible Vault.

---

## 3. Estrutura do Código Ansible

- **Idempotência**: Todos os passos de instalação do Docker e execução do container utilizam módulos idempotentes nativos do Ansible. O container é implantado via coleção `community.docker` (módulos `docker_image` e `docker_container`), sem o uso de `command` ou `shell`.
- **Ansible Vault**: A variável sensível fictícia `vault_app_admin_password` foi definida no arquivo `ansible/group_vars/all/vault.yml` e está devidamente criptografada. O arquivo `ansible/vault_pass.txt` (adicionado ao `.gitignore`) fornece a senha de descriptografia automaticamente durante o provisionamento.

---

## 4. Instruções de Execução

### Pré-requisitos
- Terraform instalado na máquina host (Windows).
- AWS CLI configurado com credenciais válidas.
- WSL com Ansible instalado.

### Passo 1: Inicializar o Repositório e os Provedores
Acesse a pasta do Terraform e inicialize os plugins:
```powershell
cd terraform
terraform init
```

### Passo 2: Criar e Selecionar o Workspace
Para implantar no ambiente de desenvolvimento (`dev`):
```powershell
terraform workspace new dev
terraform workspace select dev
```

### Passo 3: Provisionar a Infraestrutura e Configurar o Servidor
Execute o comando abaixo. O fluxo completo (criação de rede + instância + instalação do Docker + deploy do container) ocorrerá de forma automatizada:
```powershell
terraform apply -auto-approve
```

Ao final da execução, as saídas do Terraform exibirão o IP público e o endereço de acesso à aplicação:
```text
Outputs:
app_url = "http://<IP_PUBLICO>:3000"
ssh_command = "ssh -i terraform/id_rsa.pem ubuntu@<IP_PUBLICO>"
```

### Execução em Outro Workspace (Produção)
Para rodar no ambiente de produção (`prod`):
```powershell
terraform workspace new prod
terraform workspace select prod
terraform apply -auto-approve
```

---

## 5. Instruções de Destruição (Clean-up)

Para limpar todos os recursos criados na AWS para evitar cobranças indesejadas:

1. Selecione o workspace desejado:
   ```powershell
   terraform workspace select dev
   ```
2. Execute o destroy:
   ```powershell
   terraform destroy -auto-approve
   ```
3. Repita o processo para outros workspaces ativos (como `prod`).

---

## 6. Evidências de Funcionamento da Aplicação

### Acesso no Ambiente de Desenvolvimento (`dev`)
IP Público: `18.228.205.243`  
URL da Aplicação: `http://18.228.205.243:3000`

**Teste via Curl:**
```bash
$ curl -I http://18.228.205.243:3000
HTTP/1.1 200 OK
Server: nginx/1.23.3
Date: Thu, 27 Aug 2026 19:18:34 GMT
Content-Type: text/html
Content-Length: 8702
Last-Modified: Thu, 22 Dec 2022 20:49:18 GMT
Connection: keep-alive
ETag: "63a4c2ce-21fe"
Accept-Ranges: bytes
```

### Acesso no Ambiente de Produção (`prod`)
IP Público: `15.228.222.116`  
URL da Aplicação: `http://15.228.222.116:3000`

**Teste via Curl:**
```bash
$ curl -I http://15.228.222.116:3000
HTTP/1.1 200 OK
Server: nginx/1.23.3
Date: Thu, 27 Aug 2026 19:21:56 GMT
Content-Type: text/html
Content-Length: 8702
Last-Modified: Thu, 22 Dec 2022 20:49:18 GMT
Connection: keep-alive
ETag: "63a4c2ce-21fe"
Accept-Ranges: bytes
```
