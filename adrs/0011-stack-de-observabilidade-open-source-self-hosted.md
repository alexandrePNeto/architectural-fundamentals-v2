# 11. Stack de Observabilidade Open Source Self-Hosted

Date: 2026-05-23

## Status

Accepted

## Context

O sistema precisa de observabilidade completa — rastreamento de erros, métricas de aplicação e workers, e centralização de logs — para que um time pequeno consiga diagnosticar e resolver problemas em produção rapidamente, sem depender de especialistas.

No monolito modular (ADR-001), a observabilidade tem um perfil específico: em vez de rastrear chamadas HTTP entre serviços independentes, o foco é em métricas internas por módulo (Aluguel, Pagamento, Cadastro, Fiscal, Notificações, Matriz), na saúde dos workers assíncronos em EC2 separado (ADR-008) e na performance do PostgreSQL compartilhado (ADR-002) — onde contenção de conexões ou queries custosas de um módulo afetam todos os demais. A ausência de fronteiras de rede entre módulos simplifica o rastreamento de chamadas, mas exige instrumentação interna cuidadosa para distinguir a origem de erros e gargalos por módulo.

Ferramentas SaaS como Datadog e New Relic oferecem boa experiência mas têm custo proibitivo para o orçamento atual. AWS CloudWatch é nativo ao ecossistema mas limitado para buscas avançadas em logs e sem interface rica para análise sem configuração adicional complexa.

## Decision

Adotar um stack de observabilidade totalmente open source e self-hosted, sem custo de licença, composto por quatro ferramentas com responsabilidades complementares, todas rodando em instâncias EC2 dedicadas:

- **Sentry** — rastreamento e agregação de erros de aplicação em tempo real com stack trace completo; erros serão tagueados por módulo de origem para facilitar triagem
- **Prometheus** — coleta e armazenamento de métricas do monolito principal e dos workers de Fiscal e Notificações (latência por módulo, throughput, tamanho de fila RabbitMQ, erros HTTP, conexões ativas no PostgreSQL)
- **Grafana** — dashboards interativos e alertas baseados nas métricas do Prometheus
- **Graylog Open** — centralização, busca e análise de logs do monolito e dos workers; logs estruturados com campo `module` obrigatório para permitir filtragem por domínio

O custo real é apenas de infraestrutura EC2, sem limite de usuários ou ingestão de dados.

Alertas críticos configurados no Grafana:

- Worker de Fiscal ou Notificações parado por mais de 5 minutos
- Mensagens acumuladas na Dead Letter Queue do RabbitMQ (ADR-007)
- Latência do monolito acima de 2 segundos (atributo de qualidade definido no projeto)
- Conexões ativas no PostgreSQL acima de 80% do limite da instância RDS
- Cache Redis indisponível por mais de 2 minutos (ADR-013)

## Consequences

### O que fica mais fácil

- Custo zero de licença com stack profissional e amplamente adotado no mercado, compatível com o driver de baixo custo operacional do projeto.
- A ausência de limites de ingestão de logs é especialmente relevante para o Graylog Open: todos os módulos do monolito e ambos os workers podem logar com verbosidade adequada sem custo adicional por volume.
- O stack é amplamente conhecido no mercado, facilitando a contratação de profissionais já familiarizados com as ferramentas.
- Com logs estruturados com campo `module` obrigatório, o Graylog permite filtrar rapidamente por domínio — o time consegue isolar um problema no Módulo de Pagamento sem vasculhar logs de todos os outros módulos do mesmo processo.
- A instrumentação por módulo no Prometheus permite identificar qual parte do monolito está gerando gargalo de latência ou erro, sem precisar de distributed tracing entre serviços.

### O que fica mais difícil ou introduz riscos

- **Overhead operacional de quatro componentes self-hosted**: Sentry, Prometheus, Grafana e Graylog Open precisam de atualizações, backups e monitoramento próprios. O Graylog Open em particular requer MongoDB e OpenSearch como dependências, adicionando complexidade na instalação e manutenção. Para um time pequeno, esse overhead é real e contínuo.
- **Sem suporte oficial**: o time depende da comunidade para resolução de problemas em todos os componentes. Incidentes em produção que envolvam bugs ou comportamentos inesperados nas ferramentas de observabilidade podem demorar mais para ser resolvidos.
- **Disciplina de instrumentação**: no monolito modular, a distinção de logs e métricas por módulo não é automática — depende de convenção e disciplina do time para sempre incluir o campo `module` nos logs e as labels corretas nas métricas do Prometheus. Sem isso, a observabilidade perde granularidade e se torna menos útil para triagem.
- **Observabilidade da própria stack de observabilidade**: se Grafana ou Graylog ficarem indisponíveis, o time perde visibilidade do sistema exatamente quando mais precisa. A stack de observabilidade precisa de alertas próprios — ou ao menos monitoramento básico via CloudWatch como camada de fallback para as instâncias EC2 da stack.
- **Retenção de dados limitada pela capacidade do EC2**: sem limites de ingestão externos, o volume de logs e métricas é limitado pelo disco das instâncias EC2. Políticas de retenção e rotação precisam ser configuradas ativamente para evitar esgotamento de disco.

## Alternativas descartadas

Datadog foi descartado pelo custo — pode ultrapassar $500/mês facilmente com o monolito e os workers monitorados. New Relic foi descartado pelo mesmo motivo. AWS CloudWatch foi descartado pela interface limitada para buscas avançadas em logs e pela ausência de dashboards ricos sem configuração adicional complexa comparado ao Grafana + Graylog Open.