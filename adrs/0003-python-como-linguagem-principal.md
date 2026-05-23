# 3. Python como Linguagem Principal

Date: 2026-05-23

## Status

Accepted

## Context

O CWRents é desenvolvido por um time pequeno. A escolha da linguagem impacta diretamente o custo de contratação, a velocidade de desenvolvimento, a facilidade de manutenção e a capacidade de absorver novos desenvolvedores sem grande fricção.

No contexto do monolito modular adotado na ADR-001, toda a aplicação — módulos de domínio, workers assíncronos e relatórios analíticos — convive na mesma base de código e no mesmo processo principal. Isso torna a escolha da linguagem ainda mais crítica: não há fronteira de processo que permita usar linguagens diferentes por domínio sem custo significativo.

Os contextos que precisam ser atendidos são: rotas HTTP dos módulos de domínio (Aluguel, Pagamento, Cadastro, Matriz), workers assíncronos desacoplados (Fiscal e Notificações) e geração de relatórios analíticos do Módulo da Matriz.

Três alternativas foram avaliadas além do Python: Node.js, Go e Java.

## Decision

Adotar Python como linguagem principal do CWRents, utilizando FastAPI para as rotas HTTP dos módulos e SQLAlchemy como ORM para acesso ao banco de dados.

A escolha é fundamentada em três pilares: baixa curva de aprendizado (permitindo absorver novos desenvolvedores com pouca fricção), ecossistema maduro para todos os contextos presentes no monolito (FastAPI para HTTP assíncrono, Celery ou dramatiq para os workers de Fiscal e Notificações, pandas e SQLAlchemy para os relatórios analíticos do Módulo da Matriz) e custo de contratação menor comparado a Go e Java no mercado de Curitiba.

No monolito modular, a uniformidade de linguagem elimina a necessidade de pontes entre runtimes e simplifica o onboarding de novos desenvolvedores, que passam a entender o sistema inteiro sem trocar de contexto de linguagem.

## Consequences

O time consegue evoluir e manter todos os módulos do monolito com menor dependência de perfis técnicos especializados. A contratação de novos desenvolvedores é mais acessível e um desenvolvedor contratado pode atuar em qualquer módulo do sistema.

O ecossistema Python + PostgreSQL é uma das combinações mais maduras disponíveis (psycopg2, asyncpg, SQLAlchemy), sem fricção relevante na integração com o banco adotado na ADR-002.

Por rodar em processo único, o monolito se beneficia do mesmo interpretador e das mesmas dependências em todos os módulos, eliminando overhead de serialização entre serviços e simplificando o gerenciamento de pacotes.

Em cenários de altíssima concorrência no futuro, o GIL do Python pode se tornar um gargalo de throughput comparado a Go. Caso o volume de operações cresça significativamente além da escala regional, essa decisão deverá ser revisada para os workers de maior carga — que, por já serem processos separados (Fiscal e Notificações), são os candidatos naturais a uma eventual extração com mudança de linguagem.

**Alternativas descartadas:**

Node.js foi descartado por ter um ecossistema mais fraco para análise de dados e relatórios, que é uma necessidade real do Módulo da Matriz. Go foi descartado pela curva de aprendizado mais elevada e menor disponibilidade de desenvolvedores no mercado local, o que contraria o driver de baixo custo operacional. Java foi descartado pelo alto custo de contratação, curva de aprendizado mais longa e overhead de configuração incompatível com o tamanho do time e com a proposta de simplicidade do monolito modular.