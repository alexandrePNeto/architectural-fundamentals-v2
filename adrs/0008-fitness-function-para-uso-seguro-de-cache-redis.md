# 8. Fitness Function para Uso Seguro de Cache Redis

Date: 2026-05-23

## Status

Accepted

## Context

A ADR-007 define o Redis como mecanismo auxiliar de cache distribuído e rate limiting, estabelecendo que o PostgreSQL é a única fonte de verdade e que toda funcionalidade que utilizar Redis deve possuir fallback e TTL configurado.

No monolito modular (ADR-001), todos os módulos compartilham a mesma base de código e têm acesso direto ao cliente Redis. Sem enforcement automático, qualquer módulo pode progressivamente tratar o Redis como fonte de dados oficial — armazenando dados sem fallback, sem TTL, ou assumindo que o cache sempre estará disponível. Esse acoplamento se acumula silenciosamente e só se manifesta como falha crítica quando o Redis fica indisponível em produção.

## Decision

Implementar uma fitness function em duas camadas para garantir que o Redis permaneça apenas como mecanismo auxiliar de performance e proteção.

### Camada 1 — Análise estática no CI/CD (GitHub Actions)

Um script Python executado em cada pull request varre todos os arquivos que interagem com Redis e valida:

- Toda leitura do Redis possui bloco de fallback para PostgreSQL em caso de miss ou falha de conexão
- Todo `SET` no Redis possui TTL configurado explicitamente — chamadas sem `EX`, `PX` ou `EXAT` bloqueiam o PR
- Não há leituras de Redis dentro da camada de domínio de nenhum módulo (Redis é infraestrutura)

### Camada 2 — Revisão arquitetural obrigatória no Pull Request

```markdown
## Checklist Redis

- [ ] Existe fallback para PostgreSQL em caso de cache miss ou falha de conexão
- [ ] Existe TTL configurado em todo SET realizado no Redis
- [ ] Redis não é tratado como fonte oficial de dados em nenhum fluxo
- [ ] Falha no Redis não interrompe nem bloqueia o fluxo principal
- [ ] Dados críticos continuam persistidos exclusivamente no PostgreSQL
- [ ] O acesso ao Redis está isolado na camada de infraestrutura do módulo — não no domínio
```

## Consequences

### O que fica mais fácil

- O Redis permanece desacoplado da lógica crítica da aplicação, reduzindo risco arquitetural e mantendo o PostgreSQL como única fonte oficial de dados.
- Falhas no Redis causam degradação de performance, não indisponibilidade — o sistema continua operando pelo fallback para PostgreSQL.
- A validação de TTL obrigatório no CI/CD elimina a classe de bug mais comum em sistemas com cache: chaves que nunca expiram e acumulam dados desatualizados indefinidamente.
- O item do checklist sobre camada de domínio reforça a separação arquitetural da ADR-005: Redis é infraestrutura e não pode vazar para o domínio de nenhum módulo.

### O que fica mais difícil ou introduz riscos

- **Cobertura incompleta da análise estática**: o script detecta ausência de TTL e de fallback em padrões explícitos, mas não cobre abstrações — por exemplo, um wrapper de cache próprio do time que omite o TTL internamente. Nesses casos, a Camada 2 é a salvaguarda.
- **Manutenção do script**: novos padrões de uso do Redis (ex: pipelines, Lua scripts, novos clientes Python) precisam ser cobertos manualmente no script para não criar brechas.
- **Falsos positivos em rate limiting**: o rate limiting por design não possui fallback para PostgreSQL — é um contador temporário que pode ser perdido sem consequência crítica. O script precisará de uma lista de exceções documentadas para esses casos, sem criar precedente para contornar a validação de forma abusiva.
- **Disciplina do checklist**: a Camada 2 depende de disciplina humana em momentos de pressão de entrega. A Camada 1 é a salvaguarda efetiva; a Camada 2 é complementar e educativa.

## Alternativas descartadas

Validações extremamente restritivas via análise estática automática cobrindo todos os padrões possíveis foram descartadas pela complexidade de manutenção incompatível com o porte atual do projeto.

Ausência total de validação foi descartada pelo risco de transformar o Redis progressivamente em dependência crítica — risco especialmente alto no monolito modular, onde todos os módulos têm acesso irrestrito ao cliente Redis na mesma base de código.