# 5. Separação entre Domínio e Infraestrutura

Date: 2026-05-23

## Status

Accepted

## Context

O CWRents possui integrações externas com gateways de pagamento, serviços de emissão fiscal, serviços de e-mail, notificações e mensageria. Além disso, o sistema utiliza frameworks específicos como FastAPI, SQLAlchemy e RabbitMQ.

No contexto do monolito modular (ADR-001), todos os módulos de domínio — Aluguel, Pagamento, Cadastro, Fiscal, Notificações e Matriz — coexistem na mesma base de código e no mesmo processo. Essa proximidade amplifica o risco de acoplamento acidental: sem fronteiras de processo separando os módulos, um desenvolvedor pode facilmente importar um SDK externo diretamente dentro da camada de domínio de qualquer módulo, comprometendo a independência tecnológica do sistema inteiro.

O objetivo arquitetural é preservar o domínio de negócio de cada módulo o mais independente possível de detalhes técnicos, mantendo alta coesão e baixo acoplamento sem adicionar complexidade desnecessária ao projeto.

Uma arquitetura hexagonal completa com múltiplos adapters, ports e abstrações avançadas foi considerada, mas descartada por adicionar overhead excessivo ao contexto atual — time pequeno, orçamento reduzido e foco em simplicidade operacional.

## Decision

Adotar uma separação em três camadas dentro de cada módulo do monolito, aplicada de forma consistente em todos os módulos.

**Camada de domínio** — contém exclusivamente:
- Entidades e regras de negócio
- Value objects
- Contratos de repositório (interfaces)

**Camada de infraestrutura** — responsável por:
- Acesso ao banco via SQLAlchemy
- Integrações com gateways de pagamento
- Provedores de e-mail e notificações WhatsApp
- Emissão fiscal via API terceirizada
- Publicação e consumo de filas RabbitMQ
- SDKs externos em geral

**Interface pública do módulo (`<modulo>/public/`)** — camada que define o contrato do módulo com o restante do monolito:
- Serviços e casos de uso que outros módulos podem invocar
- DTOs ou tipos de dados exportados intencionalmente
- Eventos publicados pelo módulo para consumo externo

Nenhum módulo pode importar diretamente de `<modulo>/dominio/` ou `<modulo>/infraestrutura/` de outro módulo. Todo acesso entre módulos passa exclusivamente pela camada `public/` do módulo de destino. Essa convenção é análoga ao conceito de Bounded Context do DDD — cada módulo é dono do seu domínio e decide conscientemente o que expõe para os demais.

Repositories serão utilizados como abstração de persistência em todos os módulos, evitando dependência direta do domínio com ORM ou banco de dados específico.

Essa separação possibilita substituições tecnológicas com impacto reduzido nas regras de negócio. Exemplos de substituições previstas sem reescrita de domínio:

- FastAPI → Flask ou Django
- SQLAlchemy → outro ORM
- Stone → Asaas ou outro gateway de pagamento
- SendGrid → SES ou outro provedor de e-mail
- API terceirizada de NF-e → integração direta com a SEFAZ

A solução não protege 100% contra acoplamento arquitetural, mas reduz significativamente o risco sem introduzir overengineering para o porte atual do CWRents. A ADR-012 define as fitness functions automatizadas que validam os dois limites — domínio vs infraestrutura e acoplamento entre módulos — no CI/CD.

## Consequences

### O que fica mais fácil

- As regras de negócio de cada módulo permanecem limpas, coesas e independentes de tecnologias específicas, facilitando leitura, testes unitários e manutenção.
- Trocas de framework, ORM ou provedor externo podem ser feitas na camada de infraestrutura sem tocar nas regras de negócio — reduzindo o lock-in com fornecedores e aumentando a independência tecnológica do sistema.
- O uso de repositories desacopla a regra de negócio da persistência, tornando os testes unitários de domínio independentes de banco de dados.
- A camada `public/` torna explícito e intencional o contrato de cada módulo com o restante do sistema. Em vez de contratos implícitos que emergem de imports aleatórios, cada módulo declara o que expõe — o que facilita o entendimento do sistema e reduz acoplamento acidental entre módulos.
- A extração futura de qualquer módulo como serviço independente é diretamente facilitada: as fronteiras de domínio, infraestrutura e interface pública já estão definidas no código, tornando a separação física uma consequência natural da separação lógica já existente.
- A separação serve como documentação viva da arquitetura: novos desenvolvedores conseguem identificar rapidamente onde ficam as regras de negócio, onde ficam as integrações técnicas e o que cada módulo oferece para os demais.

### O que fica mais difícil ou introduz riscos

- **Manutenção da interface pública de cada módulo**: a camada `public/` precisa ser gerenciada ativamente. À medida que novos casos de uso surgem, o time precisa decidir conscientemente se algo novo entra no contrato público ou permanece detalhe interno. Sem essa disciplina, a camada `public/` tende a crescer sem critério, tornando-se um espelho do domínio interno e perdendo seu propósito.
- **Aumento da estrutura de arquivos**: três camadas por módulo significam mais diretórios e arquivos para navegar. Em um monolito com múltiplos módulos, isso se multiplica e pode gerar fricção no onboarding inicial de desenvolvedores.
- **Disciplina contínua do time**: sem fronteiras de processo, o único enforcement dos limites entre domínio e infraestrutura é a disciplina de código e a automação de CI/CD. Em momentos de pressão de entrega, atalhos diretos (importar o SQLAlchemy model no domínio, por exemplo) são tentadores e silenciosamente aceitáveis sem a fitness function ativa.
- **Isolamento incompleto**: a separação simplificada não oferece o isolamento absoluto de uma arquitetura hexagonal completa. Acoplamentos sutis podem se acumular ao longo do tempo sem serem detectados pela análise estática — especialmente imports indiretos ou uso de tipos do ORM em interfaces de domínio.
- **Overhead de abstração para casos simples**: módulos com lógica de negócio simples (ex: Cadastro, em grande parte CRUD) ganham pouco com a separação em camadas e carregam o custo estrutural sem proporcional benefício. Nesses casos, a disciplina de manter a separação pode parecer burocrática ao time.
- **Risco de interfaces de repositório anaêmicas**: ao definir contratos de repositório no domínio, há tendência de criar interfaces que espelham diretamente as operações do ORM em vez de expressar intenção de negócio. Isso cria acoplamento conceitual com a infraestrutura mesmo sem acoplamento de código.

## Alternativas descartadas

Arquitetura hexagonal completa foi descartada por adicionar excesso de abstração, adapters e complexidade operacional incompatíveis com um time pequeno e foco em baixo custo.

Acoplamento direto do domínio aos frameworks e SDKs foi descartado porque dificultaria futuras trocas tecnológicas, aumentaria o lock-in com provedores externos e comprometeria a capacidade de extrair módulos como serviços independentes no futuro.