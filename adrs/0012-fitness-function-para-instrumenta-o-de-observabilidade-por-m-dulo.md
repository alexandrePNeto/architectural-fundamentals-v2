# 15. Fitness Function para Instrumentação de Observabilidade por Módulo

Date: 2026-05-23

## Status

Accepted

## Context

A ADR-011 define que logs estruturados devem conter o campo `module` obrigatório e que erros capturados pelo Sentry devem ser tagueados com o módulo de origem. Sem essas duas convenções, a observabilidade do monolito modular (ADR-001) perde granularidade: logs e erros de todos os módulos se misturam no mesmo processo, tornando triagem e diagnóstico em produção significativamente mais lentos.

Diferente de uma arquitetura baseada em serviços — onde o processo de origem já identifica o domínio — no monolito todas as entradas de log e todos os erros partem do mesmo processo Python. A distinção por módulo depende exclusivamente de instrumentação explícita no código. Sem enforcement automático, essa convenção tende a ser negligenciada sob pressão de entrega, degradando progressivamente a utilidade da stack de observabilidade.

## Decision

Implementar uma fitness function em duas camadas para garantir que toda instrumentação de logs e erros respeite as convenções de observabilidade definidas na ADR-011.

### Camada 1 — Análise estática no CI/CD (GitHub Actions)

Um script Python executado em cada pull request varre todos os arquivos dentro dos módulos do monolito e valida:

**Logs estruturados:**
- Toda chamada ao logger que não seja em utilitários compartilhados deve incluir o campo `module` com o nome do módulo de origem (ex: `logger.info("...", extra={"module": "pagamento"})`). Chamadas sem o campo `module` bloqueiam o PR.

**Captura de erros no Sentry:**
- Toda chamada a `sentry_sdk.capture_exception()` ou `sentry_sdk.capture_message()` deve incluir a tag `module` no escopo (ex: via `sentry_sdk.set_tag("module", "fiscal")`). Capturas sem a tag bloqueiam o PR.

### Camada 2 — Revisão arquitetural obrigatória no Pull Request

```markdown
## Checklist de Observabilidade

- [ ] Todos os logs estruturados novos ou alterados incluem o campo `module`
- [ ] Todos os erros capturados no Sentry incluem a tag `module` com o módulo de origem
- [ ] Logs de infraestrutura (Redis, RabbitMQ, SQLAlchemy) estão isolados na camada de infraestrutura e não poluem logs de domínio
- [ ] Novos fluxos críticos possuem log de entrada e saída para rastreabilidade mínima
```

## Consequences

### O que fica mais fácil

- Logs no Graylog e erros no Sentry podem ser filtrados imediatamente por módulo, permitindo que o time isole um problema no Módulo de Pagamento sem vasculhar logs de todos os outros módulos do mesmo processo.
- A convenção de `module` obrigatório passa a ser verificada automaticamente — não depende de revisão manual em cada PR nem de onboarding verbal para novos desenvolvedores.
- A qualidade da observabilidade se mantém consistente ao longo da evolução do sistema, mesmo com rotatividade de time.
- O item sobre logs de infraestrutura no checklist reforça a separação da ADR-005: logs gerados por SQLAlchemy, Redis ou RabbitMQ não devem aparecer misturados com logs de domínio — eles pertencem à camada de infraestrutura e devem ser instrumentados lá.

### O que fica mais difícil ou introduz riscos

- **Cobertura incompleta em abstrações**: o script detecta chamadas diretas ao logger e ao Sentry SDK, mas não cobre wrappers ou decoradores próprios do time que encapsulem logging internamente. Se o projeto adotar um utilitário centralizado de logging, o script precisará ser atualizado para cobrir o novo padrão.
- **Falsos positivos em código compartilhado**: utilitários e middlewares que são transversais a todos os módulos (ex: middleware de autenticação, handler global de exceções) não pertencem a um módulo específico. O script precisará de uma lista de exceções documentadas para esses arquivos, com `module` definido como `"shared"` ou equivalente por convenção.
- **Manutenção do script com novos módulos**: quando novos módulos forem adicionados ao monolito, a lista de módulos válidos no script precisará ser atualizada para evitar que valores arbitrários de `module` passem na validação sem consistência com o restante do sistema.
- **Não valida qualidade do conteúdo do log**: o script garante que o campo `module` existe, mas não garante que o conteúdo do log é útil, que o nível está correto (ex: `ERROR` para erros reais, não para fluxos esperados) ou que mensagens críticas estão sendo logadas. Essa dimensão depende da cultura de qualidade do time e de revisão humana.

## Alternativas descartadas

Configuração automática de `module` via middleware global foi considerada, mas descartada: um middleware que injeta o módulo automaticamente precisaria de algum mecanismo para inferir o módulo de origem a partir do contexto da requisição — o que não é trivial em código assíncrono e em workers, onde não há contexto de request HTTP. A instrumentação explícita é mais confiável e mais legível.

Ausência de validação foi descartada porque a convenção de `module` obrigatório, sem enforcement, tende a ser negligenciada progressivamente — especialmente em código de infraestrutura e em workers, que são os contextos onde a rastreabilidade por módulo é mais crítica para diagnóstico em produção.