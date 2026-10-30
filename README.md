# FiveM on Linux — CachyOS + Lutris + Rockstar Games Launcher

Aplicativo visual para preparar o **FiveM for GTA V Enhanced** usando a instalação existente do GTA V Enhanced e o prefixo Wine do Lutris onde você já usa o Rockstar Games Launcher. O jogo pode estar em outro HD: basta selecionar a pasta que contém `GTA5_Enhanced.exe`.

> **Experimental e sem suporte oficial a Linux.** O projeto não contorna anti-cheat. A preparação pode fazer o launcher abrir e carregar a lista de servidores, mas isso não garante que seja possível conectar a servidores públicos. O método Enhanced usado aqui foi demonstrado em uma instalação Steam; a combinação Rockstar Launcher + Lutris ainda pode exigir ajustes específicos do runner. Faça backup e use por sua conta e risco.

## Instalar com um comando no CachyOS

Abra o Konsole e execute:

```bash
curl -fsSL https://raw.githubusercontent.com/VitorMartinsAlves/FiveM-on-Linux/main/install.sh | bash
```

Isso instala a interface em `~/.local/share/fivem-linux`, cria o comando `~/.local/bin/fivem-linux` e adiciona um atalho ao menu de aplicativos. Se `tkinter` não estiver instalado, o instalador oferece instalá-lo com `pacman`.

Depois, abra **FiveM on Linux** no menu ou execute:

```bash
~/.local/bin/fivem-linux
```

## Como preparar

1. Abra o GTA V Enhanced pelo Rockstar Games Launcher dentro do Lutris. Entre no modo história uma vez e feche o jogo e o launcher.
2. Abra FiveM on Linux. Confirme os três caminhos: **prefixo Lutris** (pasta com `drive_c` e `system.reg`), **pasta do GTA V Enhanced** (contém `GTA5_Enhanced.exe`) e **executável Wine** do mesmo runner configurado no Lutris.
3. Clique em **Preparar neste prefixo** e confirme. O script cria backup dos arquivos de registro antes de modificá-los, configura WebView2, prepara componentes do FiveM a partir dos manifests públicos da Cfx.re e cria um atalho no menu.
4. Clique em **Abrir FiveM** para iniciar. Na primeira execução, o cliente pode baixar vários GB de cache. Mantenha o disco com espaço livre.

A interface tenta detectar configurações do Lutris automaticamente, mas permite selecionar tudo manualmente. O GTA não é reinstalado. Se o Rockstar Launcher e o GTA usarem prefixos diferentes, selecione o prefixo que efetivamente contém o Rockstar Launcher/conta licenciada e que você usa para jogar.

## O que é alterado

- O prefixo Wine selecionado: registro WebView2, registro de instalação do FiveM e arquivos do cliente FiveM. A configuração `config.toml` recebe as chaves de raiz `gamepath`, `gamePlatform = "rockstar"` e `ui_updateChannel = "production"`, preservando as demais opções e criando backup do arquivo anterior.
- Um link de drive `R:` dentro do prefixo apontando para a pasta real do GTA.
- DLLs DirectX no prefixo, se estiverem disponíveis no runner selecionado. Os arquivos originais são copiados para o backup e as substituições Wine só são ativadas para os DLLs que realmente foram instalados.
- O cache e os backups ficam em `~/.local/share/fivem-linux/runtime`.
- Um atalho local em `~/.local/share/applications/fivem-enhanced-lutris.desktop`.

Não execute a preparação enquanto GTA, Rockstar Launcher ou outro programa estiver usando o prefixo. O script encerra o wineserver para que as alterações de registro sejam gravadas corretamente.

## Problemas conhecidos

- **Não detecta o jogo:** selecione manualmente a pasta que contém `GTA5_Enhanced.exe`, não a pasta anterior.
- **Não detecta o prefixo:** selecione a pasta raiz do prefixo Lutris; não selecione `drive_c`.
- **Janela preta:** o runner pode não expor os DLLs DXVK que o script procura. Ative DXVK na configuração do runner Lutris e confira a área Atividade.
- **O botão Connect não faz nada:** limitação confirmada no cliente FiveM Enhanced sob Wine. A execução falha dentro de `resolveServer()`, na consulta de resolução do servidor, antes de chamar o método nativo `connectTo`. Portanto, não é um problema de DNS, porta, caminho do jogo, registro ou configuração do prefixo. Alterar essas opções não corrige essa etapa.
- **Autenticação e links `cfx://`:** o redirecionamento do navegador não é encaminhado corretamente a uma instância FiveM já aberta. O Wine não consegue enumerar `\\.\\pipe\\` (erro 50), mecanismo usado pelo cliente para localizar a instância existente. Inicializar outra instância com a URL também não conclui o callback. O handler deste projeto agora registra o recebimento e mostra um aviso, sem iniciar uma segunda instância que não processaria o link.
- **Erro 401 em `/api/identities`:** esse endpoint é usado para associação opcional de contas (por exemplo, Discord/Steam); esse 401, isoladamente, não explica a falha de conexão nem significa que o ticket de entrada foi recusado.
- **Anti-cheat:** é uma limitação independente. Em Wine, o FiveM pode entrar em modo inseguro e perder recursos exigidos por servidores protegidos. Porém, a falha de conexão observada neste projeto acontece antes, em `resolveServer()`; ainda não há evidência de que o anti-cheat seja a causa desse primeiro erro. Este projeto não tenta contornar essa verificação.
- **Servidor local:** testar um servidor FXServer local em `127.0.0.1:30120` pode ajudar a separar a falha de resolução pública, mas esse caminho ainda não foi validado neste projeto.
- **Runner Wine:** selecione o executável `bin/wine` e o `wineserver` correspondente do mesmo runner. O aplicativo não mistura um wineserver do sistema com um runner Lutris.

## Créditos

A pasta `third_party/akacross` contém scripts adaptados do projeto [akacross/fivem-enhanced-linux](https://github.com/akacross/fivem-enhanced-linux), sob licença MIT, preservada junto aos arquivos. O runtime WebView2 é obtido da Microsoft e os componentes FiveM são baixados dos manifests públicos da Cfx.re na hora da preparação. Este repositório não redistribui esses binários.

O projeto não é afiliado à Cfx.re, Rockstar Games, Valve ou Lutris.

## Desinstalar ou desfazer a preparação

O instalador também instala `fivem-linux-uninstall` e adiciona **Desinstalar FiveM on Linux** ao menu de aplicativos.

No terminal:

```bash
fivem-linux-uninstall
```

O desinstalador oferece duas opções:

- **Remover apenas o aplicativo:** remove a interface e os atalhos, sem tocar no prefixo Wine.
- **Rollback completo:** encerra o Wine do prefixo selecionado e restaura registros, DLLs, configuração, mapeamento `R:`, launcher e arquivos de produto que foram substituídos ou criados. O backup fica preservado em `~/.local/share/fivem-linux/runtime/backups`.

Também é possível executar diretamente `uninstall.sh --app-only` ou `uninstall.sh --rollback`. O rollback automático só está disponível para backups criados por versões que gravam metadados de prefixo; backups antigos sem essa identificação não são aplicados automaticamente, para evitar restaurar o prefixo errado. O rollback substitui os arquivos completos de registro pelo snapshot anterior, então alterações de registro feitas no prefixo depois da preparação serão descartadas. Feche todos os programas que usam esse prefixo antes de confirmar.

O WebView2 é mantido no prefixo porque o Rockstar Games Launcher pode compartilhar esse runtime. O jogo e o Rockstar Games Launcher não são removidos.

Para usar o desinstalador sem ter o comando instalado, baixe-o para um arquivo e execute-o no terminal:

```bash
curl --proto '=https' --proto-redir '=https' -fsSL https://raw.githubusercontent.com/VitorMartinsAlves/FiveM-on-Linux/main/uninstall.sh -o /tmp/fivem-linux-uninstall.sh && bash /tmp/fivem-linux-uninstall.sh
```
