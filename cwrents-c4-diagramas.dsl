workspace "CWRents v2" "Diagramas C1, C2 e C3 do sistema CWRents — Monolito Modular" {

    model {

        # ───────────────── Pessoas ─────────────────
        cliente = person "Cliente" "Realiza aluguel de veículos pela plataforma."

        operador = person "Operador da Matriz" "Consulta relatórios financeiros e logísticos."

        # ───────────────── Sistema Principal ─────────────────
        cwrents = softwareSystem "CWRents" "Sistema de aluguel de veículos da região de Curitiba. Arquitetura baseada em monolito modular." {

            # ───────────── Monolito ─────────────
            monolito = container "Monolito CWRents" "Processo único responsável pelos módulos de negócio." "Python + FastAPI | EC2 t3.medium" {
                tags "monolith"

                # ───── Camadas PUBLIC ─────
                aluguelPublic = component "Módulo Aluguel — public" "Casos de uso expostos do domínio de aluguel." "Python Package" {
                    tags "public"
                }

                pagamentoPublic = component "Módulo Pagamento — public" "Casos de uso expostos do domínio de pagamento." "Python Package" {
                    tags "public"
                }

                cadastroPublic = component "Módulo Cadastro — public" "Casos de uso expostos do domínio de cadastro." "Python Package" {
                    tags "public"
                }

                matrizPublic = component "Módulo Matriz — public" "Casos de uso expostos do domínio da matriz." "Python Package" {
                    tags "public"
                }

                # ───── Camadas DOMAIN ─────
                aluguelDominio = component "Módulo Aluguel — domínio" "Entidades e regras de negócio de aluguel." "Python Package" {
                    tags "domain"
                }

                pagamentoDominio = component "Módulo Pagamento — domínio" "Entidades e regras de negócio de pagamento." "Python Package" {
                    tags "domain"
                }

                cadastroDominio = component "Módulo Cadastro — domínio" "Entidades e regras de negócio de cadastro." "Python Package" {
                    tags "domain"
                }

                matrizDominio = component "Módulo Matriz — domínio" "Entidades e regras de negócio da matriz." "Python Package" {
                    tags "domain"
                }

                # ───── Camadas INFRA ─────
                aluguelInfra = component "Módulo Aluguel — infra" "Repositórios SQLAlchemy e acesso ao schema aluguel." "Python Package" {
                    tags "infra"
                }

                pagamentoInfra = component "Módulo Pagamento — infra" "Gateway de pagamento e persistência." "Python Package" {
                    tags "infra"
                }

                cadastroInfra = component "Módulo Cadastro — infra" "Persistência do domínio de cadastro." "Python Package" {
                    tags "infra"
                }

                matrizInfra = component "Módulo Matriz — infra" "Redis, RabbitMQ e consultas analíticas." "Python Package" {
                    tags "infra"
                }

                # ───── Fluxo interno ─────
                aluguelPublic -> aluguelDominio "Invoca casos de uso"
                aluguelDominio -> aluguelInfra "Usa contratos de repositório"

                pagamentoPublic -> pagamentoDominio "Invoca casos de uso"
                pagamentoDominio -> pagamentoInfra "Usa contratos de repositório"

                cadastroPublic -> cadastroDominio "Invoca casos de uso"
                cadastroDominio -> cadastroInfra "Usa contratos de repositório"

                matrizPublic -> matrizDominio "Invoca casos de uso"
                matrizDominio -> matrizInfra "Usa contratos de repositório"

                # ───── Comunicação entre módulos ─────
                aluguelPublic -> pagamentoPublic "Solicita pagamento" "Interface pública"
                aluguelPublic -> cadastroPublic "Consulta cliente e veículo" "Interface pública"
            }

            # ───────────── Workers ─────────────
            workerFiscal = container "Worker Fiscal" "Processa emissão de NF-e de forma assíncrona." "Python Worker | EC2 t3.small" {
                tags "worker"
            }

            workerNotificacao = container "Worker de Notificações" "Envia e-mails e mensagens WhatsApp." "Python Worker | EC2 t3.small" {
                tags "worker"
            }

            # ───────────── Infraestrutura ─────────────
            rabbitmq = container "RabbitMQ" "Broker de mensageria para processamento assíncrono." "RabbitMQ | EC2 t3.small" {
                tags "broker"
            }

            redis = container "Redis" "Cache distribuído e rate limiting." "Redis | EC2" {
                tags "cache"
            }

            postgres = container "PostgreSQL" "Banco único separado por schemas lógicos." "PostgreSQL | AWS RDS Multi-AZ" {
                tags "database"
            }

            observabilidade = container "Observabilidade" "Sentry, Prometheus, Grafana e Graylog." "Self-hosted | EC2" {
                tags "observability"
            }
        }

        # ───────────────── Sistemas Externos ─────────────────
        gatewayPagamento = softwareSystem "Gateway de Pagamento" "Stone, Asaas ou outro parceiro."

        emissorFiscal = softwareSystem "Emissor Fiscal" "API responsável pela emissão de NF-e."

        provedorEmail = softwareSystem "Provedor de E-mail" "SES, SendGrid ou equivalente."

        provedorWhatsapp = softwareSystem "Provedor WhatsApp" "API de envio de mensagens WhatsApp."

        # ───────────────── Relações C1 ─────────────────
        cliente -> cwrents "Realiza reservas e pagamentos" "HTTPS/REST"

        operador -> cwrents "Consulta relatórios" "HTTPS/REST"

        cwrents -> gatewayPagamento "Processa pagamentos" "HTTPS/API"

        cwrents -> emissorFiscal "Emite NF-e" "HTTPS/API"

        cwrents -> provedorEmail "Envia e-mails" "SMTP/API"

        cwrents -> provedorWhatsapp "Envia mensagens WhatsApp" "HTTPS/API"

        # ───────────────── Relações C2 ─────────────────
        cliente -> monolito "Reserva veículos e realiza pagamentos" "HTTPS/REST"

        operador -> monolito "Consulta relatórios financeiros" "HTTPS/REST"

        monolito -> redis "Cache de consultas e rate limiting" "TCP/Redis"

        monolito -> rabbitmq "Publica eventos assíncronos" "AMQP"

        monolito -> postgres "Lê e grava dados" "SQL"

        rabbitmq -> workerFiscal "Consome fila fiscal" "AMQP"

        rabbitmq -> workerNotificacao "Consome filas de notificação" "AMQP"

        workerFiscal -> emissorFiscal "Emite NF-e" "HTTPS/API"

        workerFiscal -> postgres "Persiste status fiscal" "SQL"

        workerNotificacao -> provedorEmail "Envia e-mails" "SMTP/API"

        workerNotificacao -> provedorWhatsapp "Envia mensagens" "HTTPS/API"

        pagamentoInfra -> gatewayPagamento "Processa pagamento" "HTTPS/API"

        observabilidade -> monolito "Coleta métricas e logs"

        observabilidade -> workerFiscal "Coleta métricas e logs"

        observabilidade -> workerNotificacao "Coleta métricas e logs"

        observabilidade -> rabbitmq "Monitora filas e DLQ"

        observabilidade -> redis "Monitora cache e rate limiting"

        observabilidade -> postgres "Monitora queries e conexões"

        # ───────────────── Relações C3 ─────────────────
        operador -> matrizPublic "Solicita relatório"

        matrizPublic -> matrizDominio "Executa caso de uso"

        matrizDominio -> matrizInfra "Usa contrato de repositório"

        matrizInfra -> redis "Busca resultado em cache"

        matrizInfra -> postgres "Consulta schema matriz"

        matrizInfra -> redis "Armazena resultado com TTL"
    }

    views {

        systemContext cwrents "C1-Contexto" "Visão de contexto do sistema CWRents." {
            include cliente
            include operador
            include cwrents
            include gatewayPagamento
            include emissorFiscal
            include provedorEmail
            include provedorWhatsapp

            autolayout lr
        }

        container cwrents "C2-Containers" "Visão de containers do sistema." {
            include *
            autolayout lr
        }

        component monolito "C3-Modulo-Matriz" "Fluxo interno do módulo da matriz." {
            include operador
            include matrizPublic
            include matrizDominio
            include matrizInfra
            include redis
            include postgres
            include rabbitmq

            autolayout lr
        }

        theme default

        styles {

            element "Person" {
                background "#0b7285"
                color "#ffffff"
                shape person
            }

            element "Software System" {
                background "#1971c2"
                color "#ffffff"
            }

            element "monolith" {
                background "#1864ab"
                color "#ffffff"
                shape roundedbox
            }

            element "worker" {
                background "#f08c00"
                color "#ffffff"
                shape hexagon
            }

            element "broker" {
                background "#862e9c"
                color "#ffffff"
                shape pipe
            }

            element "cache" {
                background "#2b8a3e"
                color "#ffffff"
                shape cylinder
            }

            element "database" {
                background "#343a40"
                color "#ffffff"
                shape cylinder
            }

            element "observability" {
                background "#c92a2a"
                color "#ffffff"
                shape roundedbox
            }

            element "public" {
                background "#1971c2"
                color "#ffffff"
            }

            element "domain" {
                background "#74c0fc"
                color "#000000"
            }

            element "infra" {
                background "#868e96"
                color "#ffffff"
            }
        }
    }
}