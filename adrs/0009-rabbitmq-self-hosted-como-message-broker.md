# 7. RabbitMQ Self-Hosted como Message Broker

Date: 2026-05-23

## Status

Accepted

## Context

No monolito modular (ADR-001), a maior parte do processamento ocorre de forma síncrona dentro do processo principal. Porém, dois domínios possuem operações que não devem bloquear o fluxo transacional principal nem depender da disponibilidade de serviços externos no momento da requisição: emissão de nota fiscal (Módulo Fiscal) e envio de notificações por e-mail e WhatsApp (Módulo de Notificações).

Esses dois módulos são implementados como workers assíncronos em instâncias EC2 separadas (ADR-010), consumindo mensagens publicadas pelo monolito principal. A escolha do broker de mensagens impacta custo operacional, flexibilidade de roteamento e complexidade de gestão.

## Decision

Adotar RabbitMQ self-hosted em instância EC2 (t3.small) como broker de mensagens central do CWRents.

Filas persistentes e Dead Letter Queue (DLQ) serão configuradas por domínio: `fiscal`, `notificacoes.email` e `notificacoes.whatsapp`. A separação de filas por tipo de notificação — em vez de uma fila única — permite que falhas no envio de WhatsApp não bloqueiem o processamento de e-mails e vice-versa, sem necessidade de workers separados por canal.

O roteamento será feito via exchanges e routing keys do RabbitMQ, que permitem ao Módulo de Notificações distinguir e rotear mensagens por tipo sem lógica adicional no monolito principal.

O RabbitMQ será monitorado pelo Prometheus com alertas configurados no Grafana para filas paradas ou mensagens acumuladas na DLQ.

## Consequences

### O que fica mais fácil

- O processamento de emissão fiscal e envio de notificações fica isolado do fluxo transacional principal — uma falha ou lentidão no serviço de NF-e ou no WhatsApp não degrada a experiência do cliente durante a reserva ou pagamento.
- O roteamento via exchanges e routing keys é nativo ao RabbitMQ e resolve o caso do Módulo de Notificações sem código adicional: uma mensagem publicada com routing key `notificacoes.whatsapp` só chega ao consumidor de WhatsApp.
- Filas persistentes garantem que mensagens não sejam perdidas em caso de restart dos workers EC2 — o monolito publica e segue; o worker processa quando disponível.
- A DLQ por domínio permite inspecionar e reprocessar mensagens com falha sem perder rastreabilidade.
- Custo zero de licença, compatível com o driver de baixo custo operacional do projeto.

### O que fica mais difícil ou introduz riscos

- **Ponto único de falha de mensageria**: o RabbitMQ em instância única significa que uma falha da EC2 derruba a fila inteira — Fiscal e Notificações param de processar simultaneamente. Para o escopo regional atual isso é aceito com restart automático configurado e monitoramento ativo. Cluster pode ser adotado futuramente se o volume crescer.
- **Overhead operacional de instância self-hosted**: atualizações, monitoramento, backup e tunning de memória do RabbitMQ são responsabilidade do time. Para um time pequeno, cada componente self-hosted adiciona overhead operacional real e contínuo.
- **Garantia de ordem não é absoluta**: em cenários de reprocessamento via DLQ ou múltiplos consumidores, a ordem de processamento de mensagens não é garantida. Para os casos do CWRents (fiscal e notificações) isso é aceitável, mas precisa ser considerado em qualquer expansão futura do uso de filas.
- **Mensagens duplicadas em falhas de rede**: o padrão at-least-once delivery do RabbitMQ pode gerar duplicatas em cenários de falha durante o ack. Os workers de Fiscal e Notificações devem ser implementados com idempotência para lidar com reentregas sem efeitos colaterais (ex: emitir a mesma NF-e duas vezes).
- **Visibilidade limitada sem ferramenta adicional**: o management plugin do RabbitMQ oferece visibilidade básica, mas para rastreamento de mensagens individuais ao longo do fluxo (ex: "essa NF-e foi processada?") é necessário correlacionar com logs no Graylog — o que exige disciplina de instrumentação nos workers.

## Alternativas descartadas

AWS SQS foi descartado pelo custo por mensagem que cresce com volume e pela ausência de roteamento avançado por exchange e routing key — necessário para o Módulo de Notificações distinguir canais sem workers separados.

Apache Kafka foi descartado pelo overhead operacional e custo de infraestrutura completamente incompatíveis com o porte atual do projeto. Kafka resolve problemas de escala e replay de eventos que o CWRents não enfrenta na escala regional.