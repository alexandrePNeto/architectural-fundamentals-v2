# 1. Migração de Arquitetura Baseada em Serviços para Monolito Modular

Date: 2026-05-21

## Status

Accepted

## Context

O CWRents é uma plataforma de aluguel de veículos projetada para atender Curitiba e região metropolitana, operada por um time pequeno de desenvolvimento, com foco declarado em baixo custo operacional, simplicidade de manutenção e escalabilidade gradual.

A versão 1 do projeto ([architectural-fundamentals](https://github.com/alexandrePNeto/architectural-fundamentals)) adotou uma arquitetura baseada em serviços, onde cada domínio (Aluguel, Pagamento, Cadastro, Matriz) era exposto como um serviço independente orquestrado por uma API central, compartilhando um banco de dados PostgreSQL via schemas lógicos. Workers assíncronos (Fiscal e Notificações) consumiam filas RabbitMQ, e toda a stack de observabilidade era composta por Grafana, Prometheus, Graylog e Sentry rodando em infraestrutura self-hosted.

Embora essa estrutura tenha proporcionado um nível útil de desacoplamento lógico, a análise crítica da versão 1 revelou que a abordagem multi-serviço impõe custos e fricções que não são justificados pela escala atual e projetada do projeto:

- **Custo operacional elevado**: múltiplos containers HTTP independentes (um por serviço) consomem recursos de infraestrutura mesmo quando ociosos, aumentando o custo mensal de forma desproporcional à demanda real.
- **Complexidade de implantação**: a gestão de múltiplos processos independentes, com suas configurações, health checks, networking interno e ciclos de deploy separados, adiciona overhead operacional significativo para um time enxuto.
- **Banco de dados compartilhado**: como os serviços já compartilham um único PostgreSQL com schemas lógicos, a separação entre eles é predominantemente de processo — não de dados — o que enfraquece o principal argumento a favor da arquitetura distribuída e expõe o risco de acoplamento implícito via banco.
- **Dimensão do problema**: o CWRents, em seu horizonte de crescimento regional, não enfrenta a pressão de escala que justificaria o custo de operar microsserviços ou múltiplos serviços distribuídos desde o início.

Os atributos de qualidade prioritários do projeto — baixo custo de infraestrutura, facilidade de manutenção, independência tecnológica e simplicidade operacional — são mais bem atendidos por uma arquitetura que consolida os domínios em um único processo bem estruturado internamente.

## Decision

Adotar um **Monolito Modular** como estilo arquitetural principal do CWRents, substituindo a arquitetura baseada em serviços da versão 1.

O sistema será consolidado em um único processo Python + FastAPI, internamente organizado em módulos coesos e com fronteiras explícitas entre domínios:

- **Módulo de Aluguel** — reservas e contratos
- **Módulo de Pagamento** — processamento de Pix, cartão e dinheiro
- **Módulo de Cadastro** — gestão de clientes e veículos
- **Módulo da Matriz** — relatórios financeiros e logísticos
- **Módulo Fiscal** — emissão de NF-e (processamento assíncrono via RabbitMQ, mantido como worker)
- **Módulo de Notificações** — envio de e-mail e WhatsApp (processamento assíncrono via RabbitMQ, mantido como worker)

As fronteiras entre módulos serão aplicadas por convenção de código (imports controlados, interfaces explícitas entre módulos) e não por separação de processo. O banco PostgreSQL único com schemas lógicos é mantido, agora de forma consistente com a decisão arquitetural. Redis, RabbitMQ e a stack de observabilidade permanecem inalterados.

O monolito modular é projetado de forma a permitir a extração futura de módulos como serviços independentes caso o crescimento do negócio justifique — a separação interna de domínios facilita essa evolução sem necessidade de reescrita.

## Consequences

### O que fica mais fácil

- **Redução drástica de custo operacional**: um único processo em execução substitui múltiplos containers HTTP, reduzindo diretamente os gastos com instâncias de computação na AWS.
- **Simplicidade de implantação e operação**: um único artefato deployável simplifica pipelines de CI/CD, rollbacks, monitoramento e troubleshooting — especialmente relevante para um time pequeno.
- **Manutenibilidade elevada**: com módulos bem definidos dentro de uma única base de código, é mais simples navegar, testar e evoluir funcionalidades sem a fricção de coordenar múltiplos repositórios ou processos.
- **Rastreabilidade e debugging**: a ausência de chamadas HTTP internas entre serviços elimina uma classe inteira de falhas (timeouts, falhas de rede interna, inconsistências de versão de API) e simplifica o rastreamento de erros.
- **Consistência de transações**: operações que cruzam domínios (ex: criar reserva e iniciar pagamento) podem ser executadas em uma única transação de banco de dados, sem necessidade de padrões complexos como Saga.
- **Argumento executivo claro**: a redução de custo de infraestrutura é diretamente mensurável e justificável ao CEO sem necessidade de aprofundamento técnico.

### O que fica mais difícil ou introduz riscos

- **Disciplina de fronteiras entre módulos**: sem a separação física de processos, é necessário disciplina de equipe e ferramentas de análise estática para evitar que os módulos se tornem acoplados implicitamente ao longo do tempo, regredindo para um "big ball of mud".
- **Escalabilidade horizontal por domínio**: se um módulo específico (ex: Pagamento) eventualmente demandar escala independente, a extração se tornará necessária. A separação interna bem feita mitiga esse risco, mas a extração ainda implicará esforço.
- **Deploy acoplado**: qualquer mudança em qualquer módulo gera um novo deploy do sistema completo. Para a escala atual, isso é aceitável; em times maiores ou com maior frequência de deploys simultâneos por domínio, pode se tornar um gargalo.
- **Testes de integração mais amplos**: sem fronteiras de processo, é necessário cuidado extra para garantir que testes unitários por módulo não dependam implicitamente do estado de outros módulos.

### Mitigações previstas

- Definição e documentação explícita das interfaces públicas de cada módulo como parte das convenções de código do projeto.
- Uso de linters e ferramentas de análise de dependência para detectar imports cruzados não autorizados entre módulos.
- Estrutura de diretórios que espelhe os limites de módulo, facilitando a eventual extração de serviços quando e se necessário.