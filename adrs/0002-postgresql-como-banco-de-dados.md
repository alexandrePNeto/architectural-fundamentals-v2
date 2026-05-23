# 2. PostgreSQL como Banco de Dados Principal

Date: 2026-05-23

## Status

Accepted

## Context

O CWRents adota uma estratégia de banco de dados único separado por schemas lógicos por domínio (aluguel, pagamento, fiscal, notificacoes, cadastro, matriz). Essa estratégia é central para manter o custo operacional baixo e viabilizar a expansão regional futura sem necessidade de reescrita do monolito.

No contexto do monolito modular adotado na ADR-001, os módulos de domínio compartilham o mesmo processo de aplicação. O banco de dados é o ponto de persistência compartilhada entre eles, e a separação por schemas lógicos é o mecanismo que preserva o isolamento de dados entre domínios sem incorrer no custo de múltiplas instâncias de banco.

A escolha do banco de dados precisa suportar nativamente essa estratégia de schemas lógicos, além de atender às necessidades analíticas do Módulo da Matriz, que processa relatórios financeiros e logísticos consolidados sobre o mesmo banco.

MySQL foi considerado como alternativa principal pela sua velocidade de leitura em consultas simples e pelo custo ligeiramente menor no AWS RDS.

MariaDB também foi considerado devido à compatibilidade com o ecossistema MySQL e simplicidade operacional.

Oracle foi avaliado por sua robustez enterprise e maturidade em ambientes corporativos críticos.

## Decision

Adotar o PostgreSQL como banco de dados principal, hospedado no AWS RDS com configuração Multi-AZ para garantir disponibilidade.

O motivo central é que a estratégia de schemas lógicos foi desenhada para o modelo do PostgreSQL. Nele, um schema é uma namespace real dentro do mesmo banco — todos os módulos compartilham uma única instância, uma única string de conexão e uma única fatura no RDS.

No MySQL e no MariaDB, "schema" é tratado praticamente como sinônimo de database separado, o que transformaria a separação lógica planejada em uma separação física de fato, aumentando a complexidade de gestão e contradizendo o objetivo de simplicidade operacional do monolito modular.

Além disso, o PostgreSQL possui capacidades analíticas nativas superiores para o Módulo da Matriz, reduzindo a necessidade futura de soluções paralelas para relatórios e agregações complexas.

## Consequences

### O que fica mais fácil

* A estratégia de schemas lógicos funciona conforme arquitetado: uma única instância RDS, uma única fatura, e namespaces isoladas por domínio dentro do mesmo banco.
* O Módulo da Matriz se beneficia diretamente das capacidades analíticas nativas do PostgreSQL — window functions, CTEs recursivas, agregações complexas — sem necessidade de um banco separado ou camada de ETL para relatórios.
* Operações que cruzam módulos dentro do mesmo processo de aplicação podem ser executadas em uma única transação de banco de dados, aproveitando o isolamento ACID sem padrões de consistência eventual.
* A expansão regional futura é facilitada: schemas independentes por domínio permitem replicar ou particionar dados por região sem reescrever a lógica de negócio.
* O ecossistema Python + PostgreSQL é uma das combinações mais maduras disponíveis (psycopg2, asyncpg, SQLAlchemy), sem fricção de integração com a linguagem escolhida na ADR-003.
* PostgreSQL possui excelente suporte a JSON e consultas híbridas relacionais/documentais, permitindo maior flexibilidade futura sem troca de tecnologia.

### O que fica mais difícil ou introduz riscos

* **Acoplamento via banco**: no monolito modular, com todos os módulos rodando no mesmo processo e acessando o mesmo banco, um desenvolvedor pode — por descuido — escrever uma query que faz join entre schemas de domínios diferentes diretamente no banco. Isso viola os limites de módulo, cria acoplamento de dados não intencional e compromete a capacidade de extrair módulos como serviços independentes no futuro. Esse risco é mitigado pela ADR-004, que define uma fitness function automatizada para detectar cross-schema joins no CI/CD.

* **Ponto único de falha de dados**: um único banco RDS, mesmo com Multi-AZ, concentra toda a persistência do sistema. Uma degradação severa do RDS afeta todos os módulos simultaneamente — diferente de um cenário com bancos isolados por serviço, onde uma falha seria contida.

* **Contenção de conexões**: com o crescimento do volume de operações, todos os módulos competem pelo mesmo pool de conexões da instância RDS. O dimensionamento do pool e da instância precisará ser monitorado ativamente à medida que a operação escala regionalmente.

* **Migrações acopladas**: alterações de schema em um módulo são aplicadas no mesmo banco que os demais. Uma migração mal executada pode impactar a disponibilidade de módulos não relacionados. Pipelines de migração por schema e janelas de manutenção controladas mitigam esse risco.

* **Maior complexidade operacional comparado ao MySQL/MariaDB**: PostgreSQL possui mais recursos avançados, o que aumenta ligeiramente a complexidade de tuning, administração e troubleshooting quando comparado a bancos mais simples.

* **Consumo de recursos ligeiramente maior**: para workloads extremamente simples, PostgreSQL pode consumir mais memória e CPU que MySQL ou MariaDB devido às suas capacidades analíticas e mecanismos internos mais robustos.

### O que se perde ao não escolher MySQL

* Leituras simples podem ser ligeiramente mais rápidas em workloads extremamente focados em leitura.
* Menor consumo de recursos em cenários muito pequenos e simples.
* Curva operacional ligeiramente mais simples para times iniciantes.

A diferença de performance de leitura foi considerada irrelevante para o volume regional esperado do CWRents.

### O que se perde ao não escolher MariaDB

* MariaDB possui configuração inicial simples e boa compatibilidade com ferramentas do ecossistema MySQL.
* Pode apresentar menor complexidade operacional em ambientes pequenos.

Entretanto, suas capacidades analíticas, suporte avançado a schemas lógicos e ecossistema relacional avançado não atendem tão bem os requisitos arquiteturais do CWRents.

### O que se perde ao não escolher Oracle

* Oracle oferece ferramentas enterprise extremamente maduras para alta disponibilidade, tuning e observabilidade.
* Possui excelente reputação em ambientes financeiros e corporativos críticos.

Entretanto, o custo de licenciamento, suporte e operação é incompatível com o contexto de um sistema regional focado em baixo custo operacional e time pequeno. A complexidade operacional também foi considerada excessiva para o estágio atual do projeto.
