# 7. Redis como Cache Distribuído e Rate Limiting

Date: 2026-05-23

## Status

Accepted

## Context

No monolito modular (ADR-001), todos os módulos compartilham uma única instância PostgreSQL via schemas lógicos (ADR-002). Esse banco acumula responsabilidades de três naturezas distintas: operações transacionais dos módulos de domínio, consultas analíticas e relatórios do Módulo da Matriz, e leituras repetitivas de disponibilidade de veículos. Sem controle, consultas custosas de relatório podem degradar a performance de operações transacionais por contenção de conexões e CPU na mesma instância.

O sistema possui atributo de qualidade de tempo máximo de resposta de 2 segundos para consultas operacionais e relatórios mais frequentes da matriz.

Além disso, o sistema precisa de proteção básica contra abuso de API, bots e excesso de requisições automatizadas que possam degradar a disponibilidade da aplicação.

## Decision

Adotar Redis self-hosted em EC2 como camada de cache distribuído e mecanismo de rate limiting da aplicação.

O Redis será utilizado exclusivamente como mecanismo auxiliar de performance e proteção — nunca como fonte oficial de dados. O PostgreSQL permanece como única fonte de verdade. Toda funcionalidade que utilizar Redis obrigatoriamente deve possuir fallback para PostgreSQL e TTL configurado, conforme definido na ADR-0008.

O Redis será utilizado para:

- Cache de relatórios do Módulo da Matriz
- Cache de consultas repetitivas de disponibilidade de veículos
- Armazenamento temporário de respostas de consultas custosas
- Controle de rate limiting por IP ou token de autenticação

As consultas serão armazenadas utilizando hash baseado nos parâmetros da query.

Fluxo simplificado:

```text
Cliente ou Módulo da Matriz solicita consulta
            │
            ▼
      Geração do hash
            │
            ▼
          Redis
      ├── cache hit  → retorna resposta
      └── cache miss
                │
                ▼
          PostgreSQL
                │
                ▼
      salva resultado no Redis com TTL
```

O rate limiting será implementado utilizando contadores temporários no Redis para limitar requisições excessivas por IP ou token de autenticação. Falha no Redis não deve interromper o fluxo principal — apenas remover a proteção de rate limiting temporariamente.

## Consequences

### O que fica mais fácil

- O PostgreSQL recebe menos carga de consultas repetitivas e relatórios custosos, reduzindo contenção de conexões, consumo de CPU e pressão sobre a única instância compartilhada por todos os módulos.
- A experiência do usuário melhora em consultas recorrentes pela redução de latência, contribuindo diretamente para o atributo de qualidade de resposta em até 2 segundos.
- O rate limiting protege a aplicação contra abuso automatizado e bots, reduzindo risco de indisponibilidade por sobrecarga.
- Falhas no Redis degradam performance mas não causam indisponibilidade do sistema — o fallback para PostgreSQL mantém as operações funcionando, com latência maior.

### O que fica mais difícil ou introduz riscos

- **Complexidade de invalidação de cache**: cada módulo que escreve dados que afetam consultas cacheadas precisa invalidar as chaves correspondentes — ou aceitar que o cache ficará desatualizado até o TTL expirar. No monolito modular, onde múltiplos módulos escrevem no mesmo banco, rastrear quais eventos invalidam quais chaves de cache pode se tornar complexo ao longo do tempo.
- **Consistência eventual**: dados em cache podem ficar temporariamente desatualizados, especialmente relatórios do Módulo da Matriz. Esse comportamento é considerado aceitável para o contexto, mas precisa ser comunicado claramente nos relatórios (ex: "atualizado há X minutos").
- **Dependência operacional adicional**: o Redis adiciona mais um componente a monitorar, atualizar e manter. Para um time pequeno operando infraestrutura self-hosted, cada componente adicional representa overhead real.
- **Instância única como ponto de falha de performance**: sem Redis em cluster ou réplica, uma falha da instância remove o cache e o rate limiting simultaneamente, podendo gerar pico de carga no PostgreSQL enquanto o Redis não se recupera.
- **Risco de acoplamento progressivo**: sem disciplina e enforcement (ADR-014), desenvolvedores podem gradualmente tratar o Redis como fonte de dados em vez de cache auxiliar — armazenando dados sem fallback ou sem TTL. Esse risco é mitigado pela fitness function da ADR-014.

## Alternativas descartadas

AWS ElastiCache foi descartado pelo custo adicional incompatível com o porte atual do projeto — o perfil de uso do CWRents não justifica o custo de um serviço gerenciado para cache auxiliar.

Cache em memória local da aplicação foi descartado porque, com múltiplas instâncias EC2 possíveis no futuro, cada instância teria seu próprio cache independente, gerando inconsistência entre nós.

Ausência de cache foi descartada pelo risco de crescimento de carga no PostgreSQL compartilhado, especialmente com relatórios analíticos do Módulo da Matriz concorrendo com operações transacionais na mesma instância.