# 13. Workers Assíncronos para Nota Fiscal e Notificações

Date: 2026-05-23

## Status

Accepted

## Context

No monolito modular (ADR-001), a maior parte do processamento ocorre de forma síncrona dentro do processo principal. Dois módulos, porém, possuem operações com características distintas que justificam processamento fora do fluxo principal: o Módulo Fiscal (emissão de NF-e) e o Módulo de Notificações (envio de e-mail e WhatsApp).

Esses processos não exigem resposta imediata ao cliente — o aluguel já está confirmado quando disparam. Mantê-los como parte do fluxo síncrono do monolito significaria bloquear a resposta ao cliente aguardando APIs externas (emissor fiscal, SendGrid, WhatsApp) que estão fora do controle do sistema e podem ter latência variável ou falhas intermitentes.

Além disso, falhas nesses processos não devem impactar o fluxo principal de reserva e pagamento. Um erro na emissão da NF-e não deve reverter um pagamento confirmado.

## Decision

Implementar os Módulos Fiscal e de Notificações como workers assíncronos em processos Python dedicados, rodando em instâncias EC2 t3.small separadas (ADR-008), consumindo filas dedicadas no RabbitMQ (ADR-007).

Após a confirmação de um aluguel, o monolito principal publica mensagens nas filas `fiscal` e `notificacoes.email` / `notificacoes.whatsapp` via RabbitMQ. Os workers processam de forma independente e persistem o resultado no schema correspondente do PostgreSQL (ADR-002).

O Worker de Notificações utiliza o roteamento por routing keys do RabbitMQ para distinguir os canais — sem necessidade de dois workers separados. Um único processo consome ambas as filas e roteia internamente para o canal correto.

O fluxo fica assim:

```
Aluguel confirmado
      │
      ▼
Monolito CWRents
      ├──► RabbitMQ [fiscal]                 → Worker Fiscal        → Emissor NF-e (API externa)
      └──► RabbitMQ [notificacoes.email]     → Worker Notificações  → Provedor E-mail
           RabbitMQ [notificacoes.whatsapp]  →        │             → Provedor WhatsApp
```

Filas persistentes e Dead Letter Queue (DLQ) são configuradas por domínio no RabbitMQ (ADR-007). Mensagens que falham após as tentativas configuradas são enviadas para a DLQ correspondente para inspeção e reprocessamento manual sem perda de dados.

Os workers devem ser implementados com **idempotência**: em cenários de reentrega pelo RabbitMQ (at-least-once delivery), o mesmo evento processado duas vezes não deve gerar duplicidade — por exemplo, emitir a mesma NF-e duas vezes ou enviar o mesmo e-mail duplicado.

## Consequences

### O que fica mais fácil

- Falhas na emissão de NF-e ou no envio de notificações não afetam o fluxo de reserva e pagamento — o desacoplamento via fila isola completamente os processos.
- A latência de APIs externas (emissor fiscal, WhatsApp, SendGrid) não bloqueia a resposta ao cliente. O aluguel é confirmado imediatamente; a NF-e e as notificações chegam de forma assíncrona.
- Mensagens não são perdidas: filas persistentes garantem durabilidade e a DLQ captura falhas para reprocessamento sem intervenção de urgência.
- Workers idle em EC2 t3.small consomem mínimo de CPU e memória — custo significativamente menor do que containers HTTP alocados aguardando requisições.
- A separação em processos EC2 independentes isola falhas: uma instabilidade no Worker Fiscal não afeta o Worker de Notificações nem o monolito principal.

### O que fica mais difícil ou introduz riscos

- **Idempotência obrigatória**: o modelo at-least-once delivery do RabbitMQ exige que ambos os workers sejam implementados com idempotência explícita. Sem isso, reentregas em cenários de falha de rede durante o ack geram duplicidade — NF-e emitida duas vezes ou e-mail enviado em duplicata. Isso precisa ser validado em code review e testado explicitamente.
- **Rastreabilidade do fluxo assíncrono**: diagnosticar "por que essa NF-e não foi emitida?" exige correlacionar logs do monolito (publicação na fila) com logs do Worker Fiscal (consumo e resultado) e com o Graylog (ADR-011). Sem um `correlation_id` propagado do evento até o log do worker, a triagem em produção pode ser lenta.
- **Latência aceitável mas não configurável pelo cliente**: o cliente não escolhe quando recebe a notificação ou a NF-e — depende da velocidade de processamento da fila e da disponibilidade das APIs externas. Em picos de volume, a fila pode acumular e aumentar a latência percebida.
- **Overhead operacional de dois processos adicionais**: além do monolito, o time passa a operar dois workers EC2 com seus próprios ciclos de deploy, monitoramento e restart automático. Pequeno, mas real para um time enxuto.

## Alternativas descartadas

Processamento síncrono dentro do monolito foi descartado pela dependência de APIs externas no fluxo crítico de confirmação de aluguel — uma falha ou lentidão do emissor fiscal bloquearia o pagamento do cliente.

AWS Lambda foi considerado, mas o RabbitMQ self-hosted já está no ecossistema da solução e é mais barato no volume esperado. Lambda adicionaria dependência de um serviço gerenciado adicional sem benefício proporcional para o porte atual.
