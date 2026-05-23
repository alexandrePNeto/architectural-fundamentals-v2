# 8. AWS como Provedor de Nuvem Principal

Date: 2026-05-23

## Status

Accepted

## Context

O CWRents precisa de infraestrutura em nuvem com alta disponibilidade, custo controlado e compatível com a capacidade operacional de um time pequeno. Três provedores foram avaliados: AWS, GCP e Azure.

No contexto do monolito modular (ADR-001), o perfil de infraestrutura é significativamente mais simples do que em uma arquitetura baseada em serviços: um único processo de aplicação principal, workers assíncronos de Fiscal e Notificações, e uma instância de banco RDS única compartilhada por todos os módulos via schemas lógicos (ADR-002). Esse perfil reduz a quantidade de serviços gerenciados necessários e torna a escolha de provedor menos sensível a diferenciais de portfólio — o fator dominante passa a ser custo operacional e disponibilidade de profissionais no mercado local, dado que o time precisará crescer junto com o sistema.

O driver principal é custo operacional baixo aliado à disponibilidade de profissionais no mercado de Curitiba.

## Decision

Adotar AWS como provedor de nuvem principal, com os seguintes serviços:

- **RDS Multi-AZ (PostgreSQL)** — banco de dados principal com failover automático, hospedando todos os schemas lógicos de domínio em uma única instância
- **EC2 (t3.medium/large)** — monolito principal como processo longo e estável; EC2 é mais simples e mais barato que ECS/Fargate para um processo sem necessidade de orquestração ou escala horizontal automática
- **EC2 (t3.small)** — workers de Fiscal e Notificações como processos longos e sempre ativos escutando filas RabbitMQ pelo mesmo motivo
- **EC2** — RabbitMQ e stack de observabilidade self-hosted (Grafana, Prometheus, Graylog, Sentry)
- **ElastiCache (Redis)** — cache distribuído e rate limiting
- **SES** — serviço de e-mail gerenciado (substituindo SendGrid no longo prazo para reduzir custo por volume)

A escolha é fundamentada na maior base de profissionais disponíveis em Curitiba, no free tier competitivo para o estágio inicial, na maturidade dos serviços gerenciados para alta disponibilidade e na independência de ecossistemas proprietários como Microsoft e Google.

O RDS Multi-AZ é particularmente relevante para o monolito modular: como todos os módulos compartilham uma única instância de banco (ADR-002), uma indisponibilidade do banco afeta o sistema inteiro — não apenas um serviço isolado. O failover automático do Multi-AZ mitiga esse risco sem exigir operação manual.

## Consequences

### O que fica mais fácil

- O time consegue contratar desenvolvedores e engenheiros com familiaridade em AWS com menor custo e fricção do que em GCP ou Azure no mercado de Curitiba.
- Serviços gerenciados como RDS Multi-AZ e ECS reduzem o tempo gasto com operações de infraestrutura, liberando o time pequeno para entregar valor de negócio.
- O perfil simples do monolito modular — um processo principal, dois workers, um banco — reduz a superfície de configuração e monitoramento na AWS em relação ao que seria necessário em uma arquitetura de múltiplos serviços.
- A combinação RDS Multi-AZ com schemas lógicos entrega alta disponibilidade do banco com custo de uma única instância — não há necessidade de múltiplas instâncias RDS por domínio.

### O que fica mais difícil ou introduz riscos

- **Crescimento de custo não linear**: o custo pode crescer rapidamente se os serviços não forem bem dimensionados. A instância RDS, por concentrar todos os módulos, é o componente de maior impacto financeiro — um upsize de instância afeta o custo do sistema inteiro. Requer atenção ao sizing e revisão periódica via AWS Cost Explorer.
- **Lock-in de provedor**: embora a arquitetura evite lock-in de ecossistemas proprietários (sem uso de serviços exclusivos da AWS como DynamoDB ou Lambda), a operação cotidiana em RDS, ECS e ElastiCache cria familiaridade e dependência operacional que tornaria uma migração de provedor custosa no futuro.
- **Ponto único de disponibilidade de banco**: como discutido na ADR-002, todos os módulos do monolito dependem da mesma instância RDS. O Multi-AZ mitiga falhas de instância, mas não protege contra degradações de performance por contenção de conexões ou queries custosas de um módulo afetando os demais. Monitoramento ativo de conexões e query performance é necessário.
- **Self-hosted para observabilidade**: a stack de observabilidade (Grafana, Prometheus, Graylog, Sentry) rodando em EC2 exige manutenção manual de updates, backups e disponibilidade. Para um time pequeno, isso representa overhead operacional que cresce com o tempo.

### O que se perde ao não escolher GCP

- Free tier inicial mais generoso ($300 em créditos), útil no estágio de desenvolvimento.
- BigQuery nativo seria superior para analytics e relatórios de grande volume — relevante se o Módulo da Matriz precisar escalar consultas analíticas além do que o PostgreSQL suporta confortavelmente.
- Melhor integração com ferramentas de Machine Learning, útil se o CWRents quiser prever demanda por região no futuro.
- Menor disponibilidade de profissionais em Curitiba foi o fator determinante do descarte.

### O que se perde ao não escolher Azure

- Melhor integração com Office 365 e Active Directory, relevante se a matriz usar ecossistema Microsoft.
- Azure DevOps mais maduro para times que já operam com ferramentas Microsoft.
- Suporte enterprise mais forte para negociação de contratos corporativos.
- O custo de entry level mais restrito e o lock-in ao ecossistema Microsoft foram os fatores determinantes do descarte.