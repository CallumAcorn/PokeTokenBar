import Foundation

/// 앱 전체 UI 문자열 — 언어별. 단일 소스(AppLanguage)에서 파생한다.
/// 뷰는 `companion.l.<key>` 로 접근하며, language 변경 시 @Observable 로 자동 재렌더된다.
/// 포켓몬 이름은 PokéAPI 다국어 데이터(EvoLine.localizedName)에서 별도로 온다.
struct L {
    let lang: AppLanguage
    init(_ lang: AppLanguage) { self.lang = lang }

    /// `fr` is optional on purpose.
    ///
    /// Upstream's own strings pass a real French value. This fork has added strings of its own,
    /// and inventing French for them would put unreviewed translations in front of users while
    /// looking exactly as authoritative as the real ones. Falling back to English is visibly
    /// untranslated, which is the honest failure. Supply `fr` when a translation is actually
    /// reviewed.
    private func t(_ ko: String, _ en: String, _ ja: String, _ es: String, _ fr: String? = nil) -> String {
        switch lang {
        case .ko: return ko
        case .en: return en
        case .ja: return ja
        case .es: return es
        case .fr: return fr ?? en
        }
    }

    // MARK: 탭
    var home: String { t("홈", "Home", "ホーム", "Inicio", "Accueil") }
    /// 상위 탭 이름 — 안에서 도감/포획 로그를 세그먼트로 전환하므로 둘을 아우르는 말이어야 한다.
    /// (ko 가 "도감"이면 탭과 세그먼트가 같은 이름이 돼 en/ja 의 Collection/コレクション 과도 어긋난다.)
    var collection: String { t("컬렉션", "Collection", "コレクション", "Colección", "Collection") }

    // MARK: 헤더 (오늘/주/월)
    var todayTokens: String { t("오늘 사용한 토큰", "Today's tokens", "本日のトークン", "Tokens de hoy", "Tokens du jour") }
    var thisWeek: String { t("이번 주", "This week", "今週", "Esta semana", "Cette semaine") }
    var thisMonth: String { t("이번 달", "This month", "今月", "Este mes", "Ce mois-ci") }

    // MARK: 한도 섹션
    var limitsOfficial: String { t("한도 (공식)", "Limits (official)", "上限（公式）", "Límites (oficial)", "Limites (officiel)") }
    var fiveHourSession: String { t("5시간 세션", "5-hour session", "5時間セッション", "Sesión de 5 horas", "Session de 5 h") }
    var weekly: String { t("주간", "Weekly", "週間", "Semanal", "Hebdo") }
    var weeklyOpus: String { t("주간 Opus", "Weekly Opus", "週間 Opus", "Opus semanal", "Opus hebdo") }
    var weeklySonnet: String { t("주간 Sonnet", "Weekly Sonnet", "週間 Sonnet", "Sonnet semanal", "Sonnet hebdo") }
    var claudeCurrentBlock: String { t("Claude 현재 5h 블록", "Claude current 5h block", "Claude 現在の5hブロック", "Bloque actual de 5h de Claude", "Bloc 5 h actuel de Claude") }
    var reset: String { t("리셋", "Reset", "リセット", "Reinicio", "Réinit.") }
    var limitReached: String { t("한도 도달", "Limit reached", "上限到達", "Límite alcanzado", "Limite atteinte") }
    var personalSpendLimit: String { t("개인 사용 한도", "Personal spend limit", "個人利用上限", "Límite de gasto personal", "Limite de dépense personnelle") }
    var staleLimits: String { t("갱신 지연", "Stale", "更新遅延", "Desactualizado", "Périmé") }
    var refresh: String { t("갱신", "Refresh", "更新", "Actualizar", "Actualiser") }
    var limitsTapToLoad: String { t("공식 한도 불러오기", "Load official limits", "公式上限を読み込む", "Cargar límites oficiales", "Charger les limites officielles") }

    /// 프로바이더 상태 페이지 인시던트 지표 → 현지화 라벨(표시 전용).
    func providerStatusLabel(_ indicator: ProviderStatusIndicator) -> String {
        switch indicator {
        case .operational: return t("정상", "Operational", "正常", "Operativo", "Opérationnel")
        case .minor:       return t("일부 장애", "Minor issues", "一部障害", "Problemas menores", "Problèmes mineurs")
        case .major:       return t("장애", "Major outage", "障害", "Interrupción grave", "Panne majeure")
        case .critical:    return t("심각한 장애", "Critical outage", "重大障害", "Interrupción crítica", "Panne critique")
        case .maintenance: return t("점검 중", "Maintenance", "メンテナンス", "Mantenimiento", "Maintenance")
        case .unknown:     return t("상태 불명", "Status unknown", "状態不明", "Estado desconocido", "État inconnu")
        }
    }
    func plan(_ p: String) -> String { t("플랜 \(p)", "Plan \(p)", "プラン \(p)", "Plan \(p)", "Forfait \(p)") }
    func forecastReach(_ time: String) -> String {
        t("현재 속도면 \(time) 한도 도달", "At current rate, limit hit at \(time)", "現在のペースで \(time) に上限到達", "Al ritmo actual, límite alcanzado a las \(time)", "À ce rythme, limite atteinte à \(time)")
    }
    var forecastNoReach: String {
        t("현재 속도로는 리셋 전 한도 도달 없음", "Won't hit limit before reset at current rate", "現在のペースではリセット前に上限到達なし", "Al ritmo actual, no alcanzarás el límite antes del reinicio", "À ce rythme, tu n'atteindras pas la limite avant la réinit.")
    }

    /// Claude oauth/usage 신형 limits[] 엔트리 이름 — kind + 모델 스코프 기반.
    func claudeLimitEntry(kind: String?, model: String?) -> String {
        switch kind {
        case "session": return fiveHourSession
        case "weekly_all": return weekly
        case "weekly_scoped":
            // 모델명이 없으면 레거시 "주간" 행과 이름이 겹치므로 scoped 임을 구분 표기
            guard let model else { return t("주간 (모델별)", "Weekly (scoped)", "週間（モデル別）", "Semanal (por modelo)", "Hebdo (par modèle)") }
            return t("주간 \(model)", "Weekly \(model)", "週間 \(model)", "Semanal \(model)", "Hebdo \(model)")
        default:
            let base = kind ?? "limit"
            let name = model.map { " \($0)" } ?? ""
            return base.replacingOccurrences(of: "_", with: " ") + name
        }
    }

    /// Codex 한도 윈도우 이름 (windowDurationMins 기반). 알림·팝오버 공통.
    func codexWindow(_ mins: Int?) -> String {
        switch mins {
        case 300: return fiveHourSession
        case 10_080: return weekly
        case let m? where m >= 60 && m % 60 == 0:
            let h = m / 60
            return t("\(h)시간", "\(h)h", "\(h)時間", "\(h)h", "\(h) h")
        case let m?: return t("\(m)분", "\(m)m", "\(m)分", "\(m)m", "\(m) min")
        case nil: return t("한도", "Limit", "上限", "Límite", "Limite")
        }
    }

    /// Antigravity 한도 그룹 및 윈도우 이름
    var antigravityGeminiGroup: String { t("Gemini 모델군", "Gemini Models", "Gemini モデル群", "Modelos Gemini", "Modèles Gemini") }
    var antigravityThirdPartyGroup: String { t("Claude & GPT 모델군", "Claude & GPT Models", "Claude & GPT モデル群", "Modelos Claude y GPT", "Modèles Claude et GPT") }
    func antigravityWindow(window: String?, bucketId: String) -> String {
        if window == "5h" || bucketId.contains("5h") {
            return fiveHourSession
        }
        if window == "weekly" || bucketId.contains("weekly") {
            return weekly
        }
        return t("한도", "Limit", "上限", "Límite", "Limite")
    }

    // MARK: 푸터
    var refreshNow: String { t("지금 새로고침", "Refresh now", "今すぐ更新", "Actualizar ahora", "Actualiser maintenant") }
    var updated: String { t("갱신", "Updated", "更新", "Actualizado", "Mis à jour") }
    var settings: String { t("설정", "Settings", "設定", "Ajustes", "Réglages") }
    var back: String { t("뒤로", "Back", "戻る", "Atrás", "Retour") }
    var generalSectionTitle: String { t("일반", "General", "一般", "General", "Général") }
    var menuBarSectionTitle: String { t("메뉴바에 표시", "Show in menu bar", "メニューバーに表示", "Mostrar en la barra de menús", "Afficher dans la barre des menus") }
    var advancedSectionTitle: String { t("고급", "Advanced", "詳細", "Avanzado", "Avancé") }
    var advancedDisclosureLabel: String { t("고급 설정 · 진단", "Advanced · diagnostics", "詳細設定・診断", "Avanzado · diagnóstico", "Avancé · diagnostics") }
    var aboutSupportSectionTitle: String { t("정보 & 지원", "About & Support", "情報とサポート", "Acerca de y soporte", "À propos et assistance") }
    var quit: String { t("종료", "Quit", "終了", "Salir", "Quitter") }

    // MARK: 설정
    var refreshInterval: String { t("새로고침 간격", "Refresh interval", "更新間隔", "Intervalo de actualización", "Intervalle d'actualisation") }
    var language: String { t("언어", "Language", "言語", "Idioma", "Langue") }
    var menuBarItems: String { t("메뉴바 표시 항목 (복수 선택)", "Menu bar items (multi-select)", "メニューバー表示項目（複数選択）", "Elementos de la barra de menús (selección múltiple)", "Éléments de la barre des menus (sélection multiple)") }
    var todayTokensShort: String { t("오늘 토큰", "Today's tokens", "本日のトークン", "Tokens de hoy", "Tokens du jour") }
    var todayCost: String { t("오늘 비용 ($)", "Today's cost ($)", "本日のコスト ($)", "Coste de hoy ($)", "Coût du jour ($)") }
    var limitPercent: String { t("한도 %", "Limit %", "上限 %", "Límite %", "Limite %") }
    var limitDisplayModeLabel: String { t("한도 표시 방식", "Limit display", "上限の表示", "Visualización del límite", "Affichage de la limite") }
    var limitDisplayUsed: String { t("사용량", "Used", "使用量", "Usado", "Utilisé") }
    var limitDisplayRemaining: String { t("남은 양", "Remaining", "残量", "Restante", "Restant") }
    /// 팝오버 한도 행의 remaining 모드 표시 — %에 자기설명 접미사를 붙인다.
    func percentRemaining(_ percent: String) -> String {
        t("\(percent) 남음", "\(percent) left", "残り\(percent)", "\(percent) restante", "\(percent) restant")
    }
    var allOffHint: String { t("전부 끄면 캐릭터만 표시됩니다", "All off shows only the character", "すべてオフにするとキャラクターのみ表示", "Si desactivas todo, solo se mostrará el personaje", "Tout désactiver n'affiche que le personnage") }
    // MARK: 대표 포켓몬
    var floatingPetSectionTitle: String { t("플로팅 펫", "Floating Pet", "フローティングペット", "Mascota flotante", "Compagnon flottant") }
    var floatingPetEnableLabel: String { t("플로팅 펫 표시", "Show floating pet", "フローティングペットを表示", "Mostrar mascota flotante", "Afficher le compagnon flottant") }
    var floatingPetHint: String {
        t("포켓몬이 화면 위에 떠 있어요 — 드래그로 위치를 옮길 수 있어요",
          "Your Pokémon floats over the screen — drag to reposition",
          "ポケモンが画面の上に浮かびます — ドラッグで移動できます",
          "Tu Pokémon flota sobre la pantalla — arrástralo para moverlo",
          "Ton Pokémon flotte au-dessus de l'écran — fais-le glisser pour le déplacer")
    }
    var floatingPetSizeLabel: String { t("크기", "Size", "サイズ", "Tamaño", "Taille") }
    /// 지금은 한도 알림만 말풍선으로 뜨지만, 알림 종류가 늘어도 이 라벨은 그대로 쓴다.
    var floatingPetBubbleAlertsLabel: String {
        t("말풍선으로 알림 받기", "Show notifications as bubbles", "通知を吹き出しで表示", "Mostrar notificaciones como globos", "Afficher les notifications en bulles")
    }
    var floatingPetMenuOpen: String { t("토큰 바 열기", "Open Token Bar", "トークンバーを開く", "Abrir Token Bar", "Ouvrir Token Bar") }
    var floatingPetMenuHide: String {
        t("이 플로팅 펫 고정 해제", "Unpin this floating pet", "このフローティングペットのピン留めを解除",
          "Dejar de fijar esta mascota flotante")
    }
    func floatingPetHoverTokensOnly(_ tokens: String) -> String {
        t("오늘 \(tokens) 토큰", "Today: \(tokens) tokens", "今日: \(tokens) トークン", "Hoy: \(tokens) tokens", "Aujourd'hui : \(tokens) tokens")
    }
    func floatingPetHoverWithLimit(_ tokens: String, _ percent: String) -> String {
        t("오늘 \(tokens) 토큰 (한도 \(percent))",
          "Today: \(tokens) tokens (limit \(percent))",
          "今日: \(tokens) トークン（上限 \(percent)）",
          "Hoy: \(tokens) tokens (límite \(percent))",
          "Aujourd'hui : \(tokens) tokens (limite \(percent))")
    }

    var disableKeychain: String { t("자격증명 접근 끄기", "Disable credential access", "資格情報へのアクセスを無効化", "Desactivar acceso a credenciales") }
    var disableKeychainHint: String { t("켜면 Keychain 과 .credentials.json 을 아예 읽지 않습니다 — 공식 한도(%)만 숨겨지고 토큰·비용은 그대로", "When on, reads neither the Keychain nor .credentials.json — only official limits (%) are hidden; tokens/cost stay", "オンにすると Keychain も .credentials.json も読みません — 公式上限(%)のみ非表示、トークン・費用はそのまま", "Al activarlo, no lee ni el Keychain ni .credentials.json — solo se ocultan los límites oficiales (%), los tokens y el coste se mantienen") }

    var autoRestart: String { t("크래시 시 자동 재시작", "Restart automatically after a crash", "クラッシュ時に自動再起動", "Reiniciar automáticamente tras un fallo") }
    var autoRestartHint: String { t("끔이 기본. 켜면 launchd 워치독(KeepAlive)이 비정상 종료된 앱을 되살립니다 — 지속성이 늘어나 보안 도구가 주시할 수 있어요", "Off by default. When on, a launchd watchdog (KeepAlive) revives the app after an abnormal exit — more persistence, which security tooling may flag", "既定でオフ。オンにすると launchd のウォッチドッグ(KeepAlive)が異常終了したアプリを復帰させます — 常駐性が増し、セキュリティ製品が検知対象にすることがあります", "Desactivado por defecto. Si se activa, un vigilante de launchd (KeepAlive) revive la app tras una salida anómala — más persistencia, que las herramientas de seguridad pueden señalar") }

    var externalCredit: String { t("Claude Code 밖 사용도 성장에 반영", "Count non-Claude-Code use toward growth", "Claude Code 以外の利用も成長に反映", "Contar el uso fuera de Claude Code para el crecimiento") }
    var externalCreditHint: String { t("끔이 기본. Claude 웹·디자인·코워크는 로컬 기록을 남기지 않아 토큰 수를 알 수 없습니다 — 대신 로컬 토큰이 전혀 늘지 않은 구간의 주간 한도 상승분만 성장으로 환산합니다(대략치, 통계·상점 잔액에는 안 잡힘)", "Off by default. Claude Web, Design and Cowork leave no local record, so their token count is unknowable — instead, weekly limit movement during intervals where local tokens did not move at all is converted into growth (approximate; never counted into stats or the shop wallet)", "既定でオフ。Claude Web・Design・Cowork はローカル記録を残さずトークン数が分かりません — 代わりに、ローカルのトークンが全く増えなかった区間の週間上限の上昇分だけを成長に換算します（概算。統計やショップ残高には計上されません）", "Desactivado por defecto. Claude Web, Design y Cowork no dejan registro local, así que su cifra de tokens es desconocida — en su lugar, el movimiento del límite semanal en intervalos sin actividad local se convierte en crecimiento (aproximado; nunca cuenta para estadísticas ni para el saldo de la tienda)") }

    var calibrationLogging: String { t("보정 로그 기록", "Record calibration log", "キャリブレーションログを記録", "Registrar log de calibración") }
    var calibrationLoggingHint: String { t("한도 %와 토큰 수를 같이 남겨, Claude Code 밖(웹·디자인·코워크) 사용량을 토큰으로 환산할 수 있는지 조사합니다. 화면에 이미 있는 값만 로컬 파일에 적고 계정 식별자는 남기지 않습니다", "Records limit % alongside token counts, to study whether non-Claude-Code usage (Web, Design, Cowork) can be converted into a token figure. Writes only values already on screen, to a local file, with no account identifier", "上限 % とトークン数を併せて記録し、Claude Code 以外（Web・Design・Cowork）の使用量をトークンに換算できるか調べます。画面に出ている値だけをローカルファイルに書き、アカウント識別子は残しません", "Registra el % de límite junto a los tokens, para estudiar si el uso fuera de Claude Code (Web, Design, Cowork) puede convertirse en una cifra de tokens. Solo escribe valores ya visibles, en un archivo local y sin identificador de cuenta") }

    var shellResolution: String { t("셸로 도구 경로 찾기", "Find tool paths via your shell", "シェルでツールのパスを探す", "Buscar rutas de herramientas con tu shell") }
    var shellResolutionHint: String { t("끔이 기본. 켜면 `$SHELL -ilc` 로 로그인 셸을 띄워 PATH 를 읽습니다 — .zshrc 전체가 앱 안에서 실행돼요. Homebrew·mise·asdf·Volta·Bun·npm·~/.local/bin 은 켜지 않아도 찾습니다", "Off by default. When on, spawns `$SHELL -ilc` to read your PATH — your whole .zshrc runs inside the app. Homebrew, mise, asdf, Volta, Bun, npm and ~/.local/bin are found without it", "既定でオフ。オンにすると `$SHELL -ilc` でログインシェルを起動して PATH を読みます — .zshrc 全体がアプリ内で実行されます。Homebrew・mise・asdf・Volta・Bun・npm・~/.local/bin はオフでも見つかります", "Desactivado por defecto. Si se activa, lanza `$SHELL -ilc` para leer tu PATH — todo tu .zshrc se ejecuta dentro de la app. Homebrew, mise, asdf, Volta, Bun, npm y ~/.local/bin se encuentran sin esto") }
    var refreshLimitToken: String { t("한도 토큰 캐시 갱신", "Refresh limit token cache", "上限トークンキャッシュを更新", "Actualizar caché del token de límite", "Actualiser le cache du token de limite") }
    var onlyOnPress: String { t("누를 때만 Keychain 을 읽어요 — 자동 폴링은 안 읽어 팝업이 안 떠요. 토큰 만료 후 이 버튼으로 한도 갱신", "Reads Keychain only when pressed — auto-polling never does, so no pop-ups. Refresh limits here after the token expires", "押した時のみKeychainを読みます — 自動更新では読まずポップアップも出ません。トークン期限切れ後はこのボタンで上限を更新", "Solo lee Keychain al pulsar — el sondeo automático nunca lo hace, así que no aparecen avisos. Usa este botón para actualizar los límites tras la expiración del token", "Lit le Keychain uniquement sur appui — le polling automatique ne le fait jamais, donc pas de pop-up. Actualise les limites ici après l'expiration du token") }
    var launchAtLogin: String { t("로그인 시 자동 시작", "Launch at login", "ログイン時に自動起動", "Iniciar al arrancar sesión", "Lancer à l'ouverture de session") }
    var bundledOnly: String { t(".app 번들로 설치된 경우에만 사용 가능 (scripts/build-app.sh)", "Available only when installed as an .app bundle (scripts/build-app.sh)", ".appバンドルでインストールした場合のみ利用可能 (scripts/build-app.sh)", "Disponible solo si se instaló como paquete .app (scripts/build-app.sh)", "Disponible uniquement si installé comme paquet .app (scripts/build-app.sh)") }
    var notificationsSection: String { t("알림", "Notifications", "通知", "Notificaciones", "Notifications") }
    var limitNotificationsLabel: String { t("한도 알림", "Limit alerts", "上限通知", "Alertas de límite", "Alertes de limite") }
    var companionNotificationsLabel: String { t("Companion 이벤트 (부화·진화·졸업)", "Companion events (hatch / evolve / graduate)", "コンパニオンイベント（孵化・進化・卒業）", "Eventos del compañero (eclosión / evolución / graduación)", "Événements du compagnon (éclosion / évolution / diplôme)") }
    var statusChecksLabel: String { t("프로바이더 상태 확인", "Provider status checks", "プロバイダー状態チェック", "Comprobación de estado de proveedores", "Vérification de l'état des fournisseurs") }
    var statusChecksHint: String { t("Claude·OpenAI 장애를 팝오버에 표시 (알림 아님)", "Show Claude / OpenAI incidents in the popover (not a notification)", "Claude・OpenAIの障害をポップオーバーに表示（通知ではない）", "Muestra incidentes de Claude/OpenAI en el popover (no es una notificación)", "Affiche les incidents Claude / OpenAI dans le popover (pas une notification)") }
    var warning: String { t("경고", "Warning", "警告", "Aviso", "Avertissement") }
    var critical: String { t("임박", "Critical", "切迫", "Crítico", "Critique") }
    var aggregationNote: String { t("토큰 집계 기준: totalTokens (input + output + cache, 로컬 날짜)", "Token basis: totalTokens (input + output + cache, local date)", "集計基準: totalTokens (input + output + cache, ローカル日付)", "Base de cálculo: totalTokens (input + output + cache, fecha local)", "Base de calcul : totalTokens (input + output + cache, date locale)") }
    var customScanProviderLabel: String { t("프로바이더", "Provider", "プロバイダー", "Proveedor", "Fournisseur") }
    var customScanRootsLabel: String { t("추가 스캔 폴더", "Additional scan folders", "追加スキャンフォルダ", "Carpetas de escaneo adicionales", "Dossiers d'analyse supplémentaires") }
    var customScanRootsHint: String {
        t("선택한 프로바이더의 로그가 기본 위치 밖에 있을 때만. 콤마·줄바꿈 구분, * 와일드카드. 다른 프로바이더 폴더를 넣지 마세요.",
          "Only for this provider's logs outside the built-in locations. Comma/newline separated, * wildcards. Do not point at another provider's folder.",
          "選択したプロバイダーのログが既定の場所にないときだけ。カンマ・改行区切り、*ワイルドカード。別プロバイダーのフォルダは指定しないでください。",
          "Solo para los registros de este proveedor fuera de las ubicaciones integradas. Separados por coma o salto de línea; comodines *. No indiques la carpeta de otro proveedor.",
          "Uniquement pour les journaux de ce fournisseur en dehors des emplacements intégrés. Séparés par des virgules ou des retours à la ligne ; caractères génériques *. N'indique pas le dossier d'un autre fournisseur.")
    }
    var customScanRootsPlaceholder: String { t("~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions") }
    func customScanRootsMatches(_ n: Int) -> String {
        t("지금 \(n)개 추가 폴더를 스캔함", "Scans \(n) extra folder(s) now", "現在\(n)個の追加フォルダをスキャン", "Escanea \(n) carpeta(s) extra ahora", "Analyse \(n) dossier(s) supplémentaire(s) maintenant")
    }
    var close: String { t("닫기", "Close", "閉じる", "Cerrar", "Fermer") }

    // MARK: 세이브 이전 (설정 → 백업 & 이전)
    var transferSectionTitle: String { t("백업 & 이전", "Backup & Transfer", "バックアップと移行", "Copia de seguridad y transferencia", "Sauvegarde et transfert") }
    var exportSaveLabel: String { t("세이브 내보내기", "Export save", "セーブを書き出す", "Exportar partida", "Exporter la sauvegarde") }
    var exportSaveHint: String {
        t("도감·누적 토큰·가방·현재 포켓몬을 파일 하나로 저장해요",
          "Saves your Pokédex, lifetime tokens, Bag, and current Pokémon as one file",
          "図鑑・累計トークン・バッグ・現在のポケモンを1つのファイルに保存します",
          "Guarda tu Pokédex, tokens acumulados, Bolsa y Pokémon actual en un solo archivo",
          "Enregistre ton Pokédex, tes tokens cumulés, ton Sac et ton Pokémon actuel dans un seul fichier")
    }
    var exportSaveButton: String { t("내보내기…", "Export…", "書き出す…", "Exportar…", "Exporter…") }
    var importSaveLabel: String { t("세이브 불러오기", "Import save", "セーブを読み込む", "Importar partida", "Importer une sauvegarde") }
    var importSaveHint: String {
        t("다른 Mac에서 내보낸 파일을 골라 이 Mac으로 이어서 키워요",
          "Pick a file exported from another Mac and continue here",
          "他のMacから書き出したファイルを選んでこのMacで続けます",
          "Elige un archivo exportado desde otro Mac y continúa aquí",
          "Choisis un fichier exporté depuis un autre Mac et continue ici")
    }
    var importSaveButton: String { t("불러오기…", "Import…", "読み込む…", "Importar…", "Importer…") }
    var importConfirmTitle: String {
        t("이 Mac의 진행을 대체할까요?", "Replace this Mac's progress?", "このMacの進行を置き換えますか？", "¿Reemplazar el progreso de este Mac?", "Remplacer la progression de ce Mac ?")
    }
    /// 무엇이 사라지는지 수치로 적는다 — 일반적인 "정말 진행할까요?" 보다 판단에 실제로 쓸모 있다.
    /// 내보낸 시각·출처 기기를 함께 보여주는 이유: 도감 수가 같으면 3주 전 세이브도 문구가 똑같아,
    /// 오래된 파일을 되돌리는 상황을 사용자가 알아챌 단서가 없다.
    func importConfirmBody(incomingDex: Int, incomingTokens: String,
                           exportedAt: String, sourceDevice: String,
                           currentDex: Int, currentTokens: String) -> String {
        t("""
          불러올 세이브: 도감 \(incomingDex)마리 · 누적 \(incomingTokens)
          내보낸 시각: \(exportedAt) · \(sourceDevice)
          현재 이 Mac: 도감 \(currentDex)마리 · 누적 \(currentTokens)

          이 Mac의 현재 진행은 대체됩니다. 직전 상태는 상태 폴더에 백업으로 남습니다(최근 5개).
          """,
          """
          Incoming save: \(incomingDex) in Pokédex · \(incomingTokens) lifetime
          Exported: \(exportedAt) · \(sourceDevice)
          This Mac now: \(currentDex) in Pokédex · \(currentTokens) lifetime

          This Mac's current progress is replaced. The previous state is kept as a backup in the state folder (last 5).
          """,
          """
          読み込むセーブ: 図鑑 \(incomingDex)匹 · 累計 \(incomingTokens)
          書き出し日時: \(exportedAt) · \(sourceDevice)
          現在のこのMac: 図鑑 \(currentDex)匹 · 累計 \(currentTokens)

          このMacの現在の進行は置き換えられます。直前の状態は状態フォルダにバックアップとして残ります（最新5件）。
          """,
          """
          Partida a importar: Pokédex \(incomingDex) · \(incomingTokens) acumulados
          Exportada: \(exportedAt) · \(sourceDevice)
          Este Mac ahora: Pokédex \(currentDex) · \(currentTokens) acumulados

          El progreso actual de este Mac será reemplazado. El estado anterior se guarda como copia de seguridad en la carpeta de estado (últimas 5).
          """,
          """
          Sauvegarde à importer : Pokédex \(incomingDex) · \(incomingTokens) cumulés
          Exportée : \(exportedAt) · \(sourceDevice)
          Ce Mac actuellement : Pokédex \(currentDex) · \(currentTokens) cumulés

          La progression actuelle de ce Mac sera remplacée. L'état précédent est conservé en sauvegarde dans le dossier d'état (5 derniers).
          """)
    }
    var importConfirmReplace: String { t("대체", "Replace", "置き換える", "Reemplazar", "Remplacer") }
    func importSaveDone(dex: Int, tokens: String) -> String {
        t("불러왔어요 — 도감 \(dex)마리 · 누적 \(tokens)",
          "Imported — \(dex) in Pokédex · \(tokens) lifetime",
          "読み込みました — 図鑑 \(dex)匹 · 累計 \(tokens)",
          "Importado — Pokédex \(dex) · \(tokens) acumulados",
          "Importé — Pokédex \(dex) · \(tokens) cumulés")
    }
    var importErrorNotSaveFile: String {
        t("PokeTokenBar 세이브 파일이 아니에요.",
          "That isn't a PokeTokenBar save file.",
          "PokeTokenBar のセーブファイルではありません。",
          "Ese no es un archivo de partida de PokeTokenBar.",
          "Ce n'est pas un fichier de sauvegarde PokeTokenBar.")
    }
    var importErrorNewerSchema: String {
        t("더 새로운 버전에서 만든 세이브예요 — 앱을 업데이트한 뒤 다시 시도해 주세요.",
          "This save was made by a newer version — update the app and try again.",
          "より新しいバージョンで作成されたセーブです — アプリを更新してから再試行してください。",
          "Esta partida se creó con una versión más reciente — actualiza la app e inténtalo de nuevo.",
          "Cette sauvegarde a été créée par une version plus récente — mets l'app à jour et réessaie.")
    }
    /// 불러오기 실패 사유 → 사용자 문구. 뷰가 아니라 여기 두는 이유는 이 매핑이 테스트 가능해야 하기
    /// 때문이다 — 매핑이 어긋나면 `SaveTransferError` 는 LocalizedError 가 아니라서 "The operation
    /// couldn't be completed…" 같은 원문이 그대로 노출된다(조용한 품질 저하).
    func importErrorMessage(_ error: Error) -> String {
        switch error {
        case SaveTransferError.notASaveFile:  return importErrorNotSaveFile
        case SaveTransferError.newerSchema:   return importErrorNewerSchema
        case SaveTransferError.fileTooLarge:  return importErrorTooLarge
        case SaveTransferError.backupFailed:  return importErrorBackupFailed
        default: return error.localizedDescription
        }
    }
    var importErrorTooLarge: String {
        t("세이브 파일이라기엔 너무 커요 — 다른 파일을 고른 것 같아요.",
          "That file is too large to be a save — it looks like the wrong file.",
          "セーブファイルにしては大きすぎます — 別のファイルを選んだようです。",
          "Ese archivo es demasiado grande para ser una partida — parece que elegiste el archivo equivocado.",
          "Ce fichier est trop volumineux pour être une sauvegarde — ce n'est sans doute pas le bon fichier.")
    }
    /// 백업을 못 남기면 불러오기를 중단한다 — 되돌릴 수단 없이 진행을 대체하지 않기 위해서다.
    var importErrorBackupFailed: String {
        t("현재 상태를 백업하지 못해 불러오기를 중단했어요 — 진행은 그대로예요. 디스크 여유 공간을 확인해 주세요.",
          "Import stopped because the current state couldn't be backed up — your progress is untouched. Check free disk space.",
          "現在の状態をバックアップできなかったため読み込みを中止しました — 進行はそのままです。ディスクの空き容量を確認してください。",
          "Se detuvo la importación porque no se pudo hacer una copia de seguridad del estado actual — tu progreso no se ha tocado. Comprueba el espacio libre en disco.")
    }

    // MARK: 온라인 (설정 → Online) — 트레이딩/배틀용 자체 호스팅 서버 연결(옵트인)
    var onlineSectionTitle: String { t("온라인", "Online", "オンライン", "En línea") }
    var onlineServerURLLabel: String { t("서버 URL", "Server URL", "サーバーURL", "URL del servidor") }
    var onlineServerURLPlaceholder: String { t("example.com", "example.com", "example.com", "example.com") }
    var onlineDisplayNameLabel: String { t("표시 이름", "Display name", "表示名", "Nombre visible") }
    var onlineTestConnectionButton: String { t("연결 테스트", "Test Connection", "接続テスト", "Probar conexión") }
    var onlineConnectionSuccess: String { t("연결됨", "Connected", "接続済み", "Conectado") }
    func onlineConnectionFailure(_ message: String) -> String {
        t("연결 실패: \(message)", "Couldn't connect: \(message)", "接続に失敗しました: \(message)", "No se pudo conectar: \(message)")
    }

    // MARK: 문제점 알리기 (설정 → 메일 리포트)
    var reportProblem: String { t("문제점 알리기", "Report a problem", "問題を報告", "Reportar un problema", "Signaler un problème") }
    var showLogFile: String { t("로그 파일 보기", "Show log file", "ログファイルを表示", "Mostrar archivo de registro", "Afficher le fichier journal") }
    var reportAttachHint: String {
        t("메일에 로그 파일을 첨부해 주시면 원인 파악에 큰 도움이 돼요.",
          "Attaching the log file to the email helps a lot with diagnosis.",
          "メールにログファイルを添付していただくと原因の特定に役立ちます。",
          "Adjuntar el archivo de registro al correo ayuda mucho a diagnosticar el problema.",
          "Joindre le fichier journal au mail aide beaucoup au diagnostic.")
    }
    func reportMailFallback(_ address: String) -> String {
        t("메일 앱을 열 수 없어요. \(address) 로 직접 보내주세요.",
          "Couldn't open a mail app. Please email \(address) directly.",
          "メールアプリを開けません。\(address) 宛に直接お送りください。",
          "No se pudo abrir una app de correo. Escribe directamente a \(address).",
          "Impossible d'ouvrir une app de messagerie. Écris directement à \(address).")
    }
    func reportMailSubject(_ version: String) -> String {
        t("[PokeTokenBar] 문제 리포트 (v\(version))",
          "[PokeTokenBar] Problem report (v\(version))",
          "[PokeTokenBar] 問題レポート (v\(version))",
          "[PokeTokenBar] Reporte de problema (v\(version))",
          "[PokeTokenBar] Rapport de problème (v\(version))")
    }
    func reportMailBody(version: String, os: String) -> String {
        t("""
        문제 내용:
        (겪으신 문제를 적어주세요 — 언제, 어떤 화면에서, 어떻게 되었는지)


        ---
        앱 버전: v\(version)
        macOS: \(os)
        로그 파일(첨부 권장): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        What happened:
        (Describe the problem — when, on which screen, and what you saw)


        ---
        App version: v\(version)
        macOS: \(os)
        Log file (please attach): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        問題の内容:
        （いつ・どの画面で・どうなったかをご記入ください）


        ---
        アプリのバージョン: v\(version)
        macOS: \(os)
        ログファイル（添付推奨）: ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Descripción del problema:
        (Describe lo que ocurrió — cuándo, en qué pantalla y qué viste)


        ---
        Versión de la app: v\(version)
        macOS: \(os)
        Archivo de registro (se recomienda adjuntar): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Ce qui s'est passé :
        (Décris le problème — quand, sur quel écran, et ce que tu as vu)


        ---
        Version de l'app : v\(version)
        macOS: \(os)
        Fichier journal (à joindre de préférence) : ~/Library/Logs/PokeTokenBar.log
        """)
    }

    /// 새로고침 간격 라벨 (초 단위 값 → 표시). 0 = 수동.
    func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return t("수동", "Manual", "手動", "Manual", "Manuel") }
        let m = Int(seconds / 60)
        return t("\(m)분", "\(m) min", "\(m)分", "\(m) min", "\(m) min")
    }

    // MARK: 컴패니언
    var finalForm: String { t("최종 진화체", "Final form", "最終進化", "Forma final", "Forme finale") }
    func stage(_ i: Int, _ k: Int) -> String { t("진화 단계 \(i) / \(k)", "Stage \(i) / \(k)", "進化段階 \(i) / \(k)", "Etapa \(i) / \(k)", "Stade \(i) / \(k)") }
    var unknownNextEvolution: String { t("알 수 없는 다음 진화", "Unknown next evolution", "次の進化先は不明", "Próxima evolución desconocida", "Prochaine évolution inconnue") }
    var eggIncubating: String { t("🥚 부화 준비 중", "🥚 Incubating", "🥚 孵化の準備中", "🥚 Incubando", "🥚 En incubation") }
    func eggToHatch(_ amount: String) -> String { t("부화까지 \(amount)", "\(amount) to hatch", "孵化まで \(amount)", "\(amount) para eclosionar", "\(amount) avant l'éclosion") }
    func toNextEvolution(_ amount: String) -> String { t("다음 진화까지 \(amount)", "\(amount) to next evolution", "次の進化まで \(amount)", "\(amount) para la siguiente evolución", "\(amount) avant la prochaine évolution") }
    func toGraduation(_ amount: String) -> String { t("졸업까지 \(amount)", "\(amount) to graduation", "卒業まで \(amount)", "\(amount) para graduarse", "\(amount) avant le diplôme") }
    func graduated(_ name: String) -> String {
        t("\(name) 졸업 → 도감에 보존. 새 Token Egg가 도착했어요!",
          "\(name) graduated → saved to the dex. A new Token Egg has arrived!",
          "\(name) 卒業 → 図鑑に保存。新しいToken Eggが届きました！",
          "\(name) se graduó → guardado en la Pokédex. ¡Ha llegado un nuevo Token Egg!",
          "\(name) a été diplômé → conservé dans le Pokédex. Un nouveau Token Egg est arrivé !")
    }
    var dexEmptyTitle: String { t("아직 잡은 포켓몬이 없어요!", "No Pokémon caught yet!", "まだ捕まえたポケモンがいません！", "¡Todavía no has capturado ningún Pokémon!", "Aucun Pokémon capturé pour l'instant !") }
    var dexEmptyHint: String { t("토큰을 써서 첫 포켓몬을 부화시켜 보세요.", "Spend tokens to hatch your first Pokémon.", "トークンを使って最初のポケモンを孵化させましょう。", "Usa tokens para eclosionar tu primer Pokémon.", "Dépense des tokens pour faire éclore ton premier Pokémon.") }

    // MARK: 도감 요약 헤더
    var dexTitle: String { t("도감", "Pokédex", "図鑑", "Pokédex", "Pokédex") }
    func dexTotal(_ n: Int) -> String { t("총 \(n)마리", "\(n) total", "全\(n)匹", "\(n) en total", "\(n) au total") }
    /// 포획 로그 = 개체 단위 기록(같은 라인 중복이 정상). 도감 = 종 단위 집계.
    var catchLogTitle: String { t("포획 로그", "Catch log", "捕獲ログ", "Registro de capturas", "Journal de captures") }
    /// 도감 총계는 개체가 아니라 종 수 — 로그의 dexTotal("총 N마리")과 단위가 다르다.
    var pcTitle: String { t("PC", "PC", "PC", "PC") }
    func pcLevel(_ n: Int) -> String { t("Lv.\(n)", "Lv.\(n)", "Lv.\(n)", "Nv.\(n)") }
    var pcSetTraining: String { t("훈련 대상으로 설정", "Set as training", "育成対象に設定", "Poner en entrenamiento") }

    // MARK: 스탯
    var pcStatsTitle: String { t("능력치", "Stats", "ステータス", "Estadísticas") }
    var statHP: String { t("HP", "HP", "HP", "PS") }
    var statAttack: String { t("공격", "Atk", "こうげき", "Ataq") }
    var statDefense: String { t("방어", "Def", "ぼうぎょ", "Def") }
    var statSpecialAttack: String { t("특공", "SpA", "とくこう", "AtEsp") }
    var statSpecialDefense: String { t("특방", "SpD", "とくぼう", "DefEsp") }
    var statSpeed: String { t("스피드", "Spe", "すばやさ", "Vel") }
    /// 타입 표시명 — 본가 공식 번역(PokéAPI /type/{name} names 기준).
    func typeName(_ type: PokemonType) -> String {
        switch type {
        case .normal:   return t("노말", "Normal", "ノーマル", "Normal")
        case .fire:     return t("불꽃", "Fire", "ほのお", "Fuego")
        case .water:    return t("물", "Water", "みず", "Agua")
        case .electric: return t("전기", "Electric", "でんき", "Eléctrico")
        case .grass:    return t("풀", "Grass", "くさ", "Planta")
        case .ice:      return t("얼음", "Ice", "こおり", "Hielo")
        case .fighting: return t("격투", "Fighting", "かくとう", "Lucha")
        case .poison:   return t("독", "Poison", "どく", "Veneno")
        case .ground:   return t("땅", "Ground", "じめん", "Tierra")
        case .flying:   return t("비행", "Flying", "ひこう", "Volador")
        case .psychic:  return t("에스퍼", "Psychic", "エスパー", "Psíquico")
        case .bug:      return t("벌레", "Bug", "むし", "Bicho")
        case .rock:     return t("바위", "Rock", "いわ", "Roca")
        case .ghost:    return t("고스트", "Ghost", "ゴースト", "Fantasma")
        case .dragon:   return t("드래곤", "Dragon", "ドラゴン", "Dragón")
        case .dark:     return t("악", "Dark", "あく", "Siniestro")
        case .steel:    return t("강철", "Steel", "はがね", "Acero")
        case .fairy:    return t("페어리", "Fairy", "フェアリー", "Hada")
        }
    }
    var pcVitaminsTitle: String { t("비타민 먹이기", "Feed a vitamin", "栄養ドリンクを与える", "Dar una vitamina") }
    var pcIvEvTitle: String { t("개체값 · 노력치", "IVs & EVs", "個体値・努力値", "IVs y EVs") }
    var ivLabel: String { t("개체값", "IV", "個体値", "IV") }
    var evLabel: String { t("노력치", "EV", "努力値", "EV") }

    // MARK: 거래
    var tradeTitle: String { t("거래", "Trade", "交換", "Intercambio") }
    var tradePickOffer: String { t("보낼 포켓몬을 골라주세요", "Pick a Pokémon to offer", "送るポケモンを選んでください", "Elige un Pokémon para ofrecer") }
    var tradeNoBenchedMons: String { t("PC에 훈련 중이 아닌 포켓몬이 없어요.\n먼저 훈련 대상을 바꾸거나 새 알을 부화시켜 보세요.", "You don't have any benched Pokémon to offer.\nSwitch your training focus or hatch a new egg first.", "PCに育成中でないポケモンがいません。\nまず育成対象を切り替えるか、新しい卵を孵化させてください。", "No tienes ningún Pokémon en el banco para ofrecer.\nCambia tu Pokémon en entrenamiento o eclosiona un huevo primero.") }
    var tradeCreateButton: String { t("이 포켓몬으로 거래 시작", "Start trade with this Pokémon", "このポケモンで交換を開始", "Iniciar intercambio con este Pokémon") }
    var tradeWaitingForJoin: String { t("친구가 링크를 열기를 기다리는 중…", "Waiting for a friend to open the link…", "友達がリンクを開くのを待っています…", "Esperando a que un amigo abra el enlace…") }
    var tradeShareLink: String { t("링크 공유", "Share link", "リンクを共有", "Compartir enlace") }
    var tradeCopyLink: String { t("링크 복사", "Copy link", "リンクをコピー", "Copiar enlace") }
    var tradeCopied: String { t("복사됨", "Copied", "コピーしました", "Copiado") }
    var tradeWaitingForCounterpart: String { t("상대가 포켓몬을 고르는 중…", "Waiting for the other trainer to pick…", "相手がポケモンを選んでいます…", "Esperando a que el otro entrenador elija…") }
    func tradeReviewOffer(_ name: String) -> String {
        t("\(name)님이 이 포켓몬을 제안했어요", "\(name) is offering this Pokémon", "\(name) さんがこのポケモンを提案しました", "\(name) te ofrece este Pokémon")
    }
    var tradeConfirmButton: String { t("거래 확정", "Confirm trade", "交換を確定", "Confirmar intercambio") }
    var tradeCancelButton: String { t("취소", "Cancel", "キャンセル", "Cancelar") }
    func tradeCompleted(_ received: String, from: String) -> String {
        t("\(from)님에게서 \(received)을(를) 받았어요!", "You received \(received) from \(from)!", "\(from) さんから \(received) を受け取りました！", "¡Recibiste a \(received) de \(from)!")
    }
    var tradeDoneButton: String { t("완료", "Done", "完了", "Listo") }
    var tradeFailedTitle: String { t("거래에 실패했어요", "Trade failed", "交換に失敗しました", "El intercambio falló") }
    var tradeAuthErrorMessage: String {
        t("서버에 연결할 수 없어요. 설정에서 서버 주소가 정확한지, 테스트가 성공했는지 확인해 주세요.",
          "Couldn't reach the server. Make sure the server URL is correct and tested in Settings.",
          "サーバーに接続できませんでした。設定でサーバーURLが正しいか、テストが成功しているか確認してください。",
          "No se pudo conectar con el servidor. Comprueba que la URL del servidor sea correcta y esté probada en Ajustes.") }
    var tradeExpiredTitle: String { t("이 거래 링크는 만료됐어요", "This trade link has expired", "この交換リンクは期限切れです", "Este enlace de intercambio ha caducado") }
    var tradeTryAgainButton: String { t("다시 시도", "Try again", "もう一度試す", "Intentar de nuevo") }
    func tradeJoinPrompt(_ server: String) -> String {
        t("\(server)에서 온 거래 초대예요. 참가할까요?", "You've been invited to a trade on \(server). Join?", "\(server) からの交換の招待です。参加しますか？", "Te han invitado a un intercambio en \(server). ¿Quieres unirte?")
    }
    var tradeJoinButton: String { t("참가", "Join", "参加", "Unirse") }
    func tradeDifferentServerConfirm(_ server: String) -> String {
        t("지금은 다른 서버에 연결돼 있어요. \(server)(으)로 바꾸고 거래에 참가할까요?",
          "You're currently connected to a different server. Switch to \(server) and join this trade?",
          "現在別のサーバーに接続されています。\(server) に切り替えて交換に参加しますか？",
          "Actualmente estás conectado a otro servidor. ¿Cambiar a \(server) y unirte a este intercambio?")
    }
    /// Shown when an invite link names a server and none is configured yet. The link can come from
    /// anywhere — a web page can open `poketokenbar://` — so the host is always named and always
    /// confirmed before the app talks to it or offers anything to it.
    func tradeConnectServerConfirm(_ server: String) -> String {
        t("이 초대 링크는 \(server) 서버를 사용합니다. 연결하고 거래에 참가할까요?",
          "This invite link uses the server \(server). Connect to it and join this trade?",
          "この招待リンクはサーバー \(server) を使用します。接続して交換に参加しますか？",
          "Este enlace de invitación usa el servidor \(server). ¿Conectar y unirte a este intercambio?")
    }
    var tradeEntryPointHelp: String { t("포켓몬 거래", "Trade a Pokémon", "ポケモン交換", "Intercambiar un Pokémon") }
    /// 링크를 탭해서 못 여는 경우(다른 기기에서 텍스트로 받음, 링크 핸들러 미등록 등)의 대안 입력.
    var tradePasteInviteLinkPlaceholder: String {
        t("초대 링크 붙여넣기", "Paste invite link", "招待リンクを貼り付け", "Pegar enlace de invitación")
    }
    var tradeInvalidInviteLink: String {
        t("유효한 거래 링크가 아니에요", "That's not a valid trade link", "有効な交換リンクではありません", "Ese no es un enlace de intercambio válido")
    }
    var tradeDisplayNameRequired: String {
        t("설정에서 표시 이름(1~60자)을 먼저 설정해주세요", "Set a display name (1–60 characters) in Settings first",
          "先に設定で表示名（1〜60文字）を設定してください", "Primero configura un nombre para mostrar (1–60 caracteres) en Ajustes")
    }
    var tradeInvalidOfferMessage: String {
        t("제안이 유효하지 않아요 — 설정에서 표시 이름(1~60자)을 확인해주세요.",
          "That offer wasn't valid — check your display name in Settings (1–60 characters).",
          "オファーが無効です — 設定で表示名（1〜60文字）を確認してください。",
          "Esa oferta no era válida: comprueba tu nombre para mostrar en Ajustes (1–60 caracteres).")
    }
    var tradeNotParticipantMessage: String {
        t("더 이상 이 거래에 참여하고 있지 않아요.", "You're not part of this trade anymore.",
          "このトレードにはもう参加していません。", "Ya no formas parte de este intercambio.")
    }
    var tradeConflictMessage: String {
        t("이 거래는 이미 진행됐어요 — 새로 시작해주세요.", "This trade already moved on — try starting a new one.",
          "この交換はすでに進行しています — 新しく始めてください。", "Este intercambio ya avanzó — intenta empezar uno nuevo.")
    }

    // MARK: Evolution lock
    var evolutionLockedHelp: String { t("진화 잠김 — 탭하면 해제(경험치는 계속 쌓여요)", "Evolution locked — tap to unlock (still earns XP)", "進化ロック中 — タップで解除（経験値は引き続き貯まります）", "Evolución bloqueada — toca para desbloquear (sigue ganando XP)") }
    var evolutionUnlockedHelp: String { t("탭하면 이 포켓몬의 진화를 막아요", "Tap to lock this Pokémon's evolution", "タップでこのポケモンの進化をロックします", "Toca para bloquear la evolución de este Pokémon") }
    var evolutionLockedBadge: String { t("잠김", "Locked", "ロック中", "Bloqueado") }
    var pcLockEvolution: String { t("진화 잠그기", "Lock evolution", "進化をロック", "Bloquear evolución") }
    var pcUnlockEvolution: String { t("진화 잠금 해제", "Unlock evolution", "進化ロックを解除", "Desbloquear evolución") }
    var pcSetFloating: String { t("플로팅 펫으로 추가", "Add as floating pet", "フローティングペットに追加", "Añadir como mascota flotante") }
    var pcUnsetFloating: String { t("플로팅 펫에서 제거", "Remove floating pet", "フローティングペットから削除", "Quitar mascota flotante") }
    /// 도감 총계는 개체가 아니라 종 수 — 로그의 dexTotal("총 N마리")과 단위가 다르다.
    /// n = 언락한 종 수, total = 이 앱이 지원하는 전체 종 수(PokemonAssets.animatedSpeciesIDs, 649 — 애니메이션
    /// 스프라이트 상한). 진짜 도감처럼 "잡은/전체" 진행도를 보여준다.
    func dexSpeciesTotal(_ n: Int, _ total: Int) -> String {
        t("\(n)/\(total)종", "\(n)/\(total) species", "\(n)/\(total)種", "\(n)/\(total) especies")
    }
    func dexPageLabel(_ page: Int, _ total: Int) -> String {
        t("\(total)페이지 중 \(page)페이지", "Page \(page) of \(total)", "\(total)ページ中 \(page)ページ", "Página \(page) de \(total)", "Page \(page) sur \(total)")
    }
    var dexPagePrev: String { t("이전 페이지", "Previous page", "前のページ", "Página anterior", "Page précédente") }
    var dexPageNext: String { t("다음 페이지", "Next page", "次のページ", "Página siguiente", "Page suivante") }
    var dexRaising: String { t("키우는 중", "Raising", "育成中", "Criando", "En élevage") }
    var rarityCommon: String { t("일반", "Common", "ノーマル", "Común", "Commun") }
    var rarityUncommon: String { t("고급", "Uncommon", "アンコモン", "Poco común", "Peu commun") }
    var rarityRare: String { t("희귀", "Rare", "レア", "Raro", "Rare") }
    var rarityLegendary: String { t("전설", "Legendary", "伝説", "Legendario", "Légendaire") }
    var dexFilterHint: String { t("탭하면 이 희귀도만 보기 · 다시 탭하면 전체", "Tap to show only this rarity · tap again to clear", "タップでこの希少度のみ表示・再タップで全体", "Toca para ver solo esta rareza · toca de nuevo para ver todo", "Touche pour n'afficher que cette rareté · touche à nouveau pour tout afficher") }
    /// 도감 칸의 ✨ 를 읽어주는 명사 — 이모지는 스크린리더가 일관되게 읽지 못한다.
    var dexShinyLabel: String { t("이로치", "Shiny", "色違い", "Variocolor", "Chromatique") }
    func acquisitionLabel(_ source: AcquisitionSource) -> String {
        switch source {
        case .egg: return t("부화", "Hatched", "孵化", "Eclosión")
        case .trade(let from):
            guard let from, !from.isEmpty else { return t("거래", "Traded", "交換", "Intercambio") }
            return t("\(from)에게서 거래", "Traded from \(from)", "\(from)から交換", "Intercambiado de \(from)")
        }
    }
    var dexNormalLabel: String { t("일반", "Normal", "通常色", "Normal") }
    var dexShinyLocked: String { t("이 종의 이로치를 아직 못 잡았어요", "Haven't caught this species' shiny yet", "この種の色違いはまだ捕まえていません", "Aún no has capturado la variante variocolor de esta especie") }
    var dexStatRangeTitle: String { t("능력치 범위 (Lv.100 기준)", "Stat range (at Lv.100)", "ステータス範囲（Lv.100基準）", "Rango de estadísticas (a Nv.100)") }
    var dexAbilitiesTitle: String { t("가능한 특성", "Possible abilities", "とくせいの可能性", "Habilidades posibles") }
    func rarityLabel(_ r: Rarity) -> String {
        switch r {
        case .common:    return rarityCommon
        case .uncommon:  return rarityUncommon
        case .rare:      return rarityRare
        case .legendary: return rarityLegendary
        }
    }

    // 상태 한 줄
    var statusEgg: String { t("곧 깨어나요.", "Hatching soon.", "もうすぐ孵化します。", "Está a punto de eclosionar.", "Bientôt l'éclosion.") }
    var statusIdle: String { t("오늘은 조용히 자리를 지켜요.", "Keeping quiet today.", "今日は静かにしています。", "Hoy se mantiene tranquilo.", "Tranquille aujourd'hui.") }
    var statusWorking: String { t("오늘의 작업 흔적이 쌓이고 있어요.", "Today's work is piling up.", "本日の作業が積み重なっています。", "El trabajo de hoy se va acumulando.", "Le travail du jour s'accumule.") }
    var statusFocus: String { t("지금은 집중 모드예요.", "In focus mode now.", "今は集中モードです。", "Ahora está en modo concentración.", "En mode concentration.") }
    var statusTired: String { t("한도에 가까워요. 잠깐 쉬어도 괜찮아요.", "Close to the limit. A short break is fine.", "上限が近いです。少し休んでも大丈夫。", "Está cerca del límite. Un pequeño descanso no vendría mal.", "Proche de la limite. Une petite pause ne fait pas de mal.") }
    var statusSleep: String { t("지금은 자고 있어요.", "Sleeping now.", "今は眠っています。", "Ahora está durmiendo.", "En train de dormir.") }
    func statusEvolved(_ name: String) -> String { t("\(name)(으)로 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！", "¡Evolucionó a \(name)!", "A évolué en \(name) !") }
    var statusGrew: String { t("성장했어요!", "It grew!", "成長しました！", "¡Ha crecido!", "Il a grandi !") }

    // MARK: companion 이벤트 시스템 알림
    var notifHatchTitle: String { t("🥚 부화!", "🥚 Hatched!", "🥚 孵化！", "🥚 ¡Eclosionó!", "🥚 Éclosion !") }
    func notifHatchBody(_ name: String) -> String { t("알에서 \(name)이(가) 나왔어요!", "\(name) hatched from the egg!", "タマゴから \(name) が生まれました！", "¡\(name) salió del huevo!", "\(name) est sorti de l'œuf !") }
    var notifShinyHatchTitle: String { t("✨ 이로치 포켓몬!", "✨ Shiny Pokémon!", "✨ 色違いポケモン！", "✨ ¡Pokémon variocolor!", "✨ Pokémon chromatique !") }
    func notifShinyHatchBody(_ name: String) -> String { t("이로치 \(name)이(가) 태어났어요! (1/64)", "A shiny \(name) hatched! (1 in 64)", "色違いの \(name) が生まれました！(1/64)", "¡Nació un \(name) variocolor! (1 entre 64)", "Un \(name) chromatique est né ! (1 sur 64)") }
    var eggImminent: String { t("곧 부화해요!", "About to hatch!", "もうすぐ孵化！", "¡Está a punto de eclosionar!", "Sur le point d'éclore !") }
    /// 첫 실행(아직 토큰 적립 0) 안내 — "왜 아무 일도 안 일어나지"를 방지.
    var eggFirstRunHint: String {
        t("로컬 AI 코딩 도구의 사용량으로 자라요. 약 5M 토큰을 쓰면 알이 부화해요.",
          "Grows from your local AI coding usage. Your egg hatches after ~5M tokens.",
          "ローカルの AI コーディング使用量で育ちます。約5Mトークンでタマゴが孵化します。",
          "Crece con el uso de tus herramientas locales de programación con IA. Tu huevo eclosiona tras unos 5M de tokens.",
          "Il grandit avec l'usage de tes outils de code IA locaux. Ton œuf éclôt après environ 5M de tokens.") }
    var notifEvolveTitle: String { t("✨ 진화!", "✨ Evolved!", "✨ 進化！", "✨ ¡Evolucionó!", "✨ Évolution !") }
    func notifEvolveBody(_ name: String) -> String { t("\(name)(으)로 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！", "¡Evolucionó a \(name)!", "A évolué en \(name) !") }
    // 메타몽 위장 리빌 — 진화 못 하는 메타몽이 첫 진화 순간 정체를 드러낸다.
    var notifDittoRevealTitle: String { t("🎭 어라? 메타몽!", "🎭 Huh? It's Ditto!", "🎭 あれ？メタモン！", "🎭 ¿Eh? ¡Es Ditto!", "🎭 Hein ? C'est Métamorph !") }
    func notifDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데 — 사실은 메타몽이었어요!", "You thought it was \(disguise) — it was Ditto all along!", "\(disguise) だと思ってた… 実はメタモンでした！", "Pensabas que era \(disguise) — ¡en realidad era Ditto!", "Tu croyais que c'était \(disguise) — c'était Métamorph depuis le début !") }
    var notifShinyDittoRevealTitle: String { t("🎭✨ 어라? 이로치 메타몽!", "🎭✨ Huh? A shiny Ditto!", "🎭✨ あれ？色違いメタモン！", "🎭✨ ¿Eh? ¡Un Ditto variocolor!", "🎭✨ Hein ? Un Métamorph chromatique !") }
    func notifShinyDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데 — 이로치 메타몽이었어요! (1/64)", "You thought it was \(disguise) — it was a shiny Ditto! (1 in 64)", "\(disguise) だと思ってた… 色違いのメタモンでした！(1/64)", "Pensabas que era \(disguise) — ¡era un Ditto variocolor! (1 entre 64)", "Tu croyais que c'était \(disguise) — c'était un Métamorph chromatique ! (1 sur 64)") }
    var notifGraduateTitle: String { t("🎓 졸업!", "🎓 Graduated!", "🎓 卒業！", "🎓 ¡Graduado!", "🎓 Diplômé !") }
    func notifGraduateBody(_ name: String) -> String { t("\(name) — 도감에 보존! 새 알이 도착했어요.", "\(name) — saved to your Pokédex! A new egg has arrived.", "\(name) — 図鑑に保存！新しいタマゴが届きました。", "\(name) — ¡guardado en tu Pokédex! Ha llegado un nuevo huevo.", "\(name) — conservé dans ton Pokédex ! Un nouvel œuf est arrivé.") }

    // MARK: Claude 한도 토큰 갱신 오류 (친절 안내)
    func limitRefreshHTTPError(_ status: Int) -> String {
        if status == 401 || status == 403 {
            return t(
                "Claude 자격증명이 만료됐거나 권한이 없어요 (\(status)). Claude Code 로그인을 확인하세요. Codex만 쓴다면 무시해도 됩니다 — Codex 한도는 따로 표시돼요.",
                "Claude credential is expired or unauthorized (\(status)). Check that you're signed in to Claude Code. If you only use Codex you can ignore this — Codex limits show separately.",
                "Claude の認証情報が期限切れか権限がありません (\(status))。Claude Code にサインインしているか確認してください。Codex のみ使用する場合は無視できます — Codex の上限は別に表示されます。",
                "La credencial de Claude expiró o no tiene permisos (\(status)). Comprueba que has iniciado sesión en Claude Code. Si solo usas Codex, puedes ignorar esto — los límites de Codex se muestran aparte.",
                "L'identifiant Claude a expiré ou n'est pas autorisé (\(status)). Vérifie que tu es connecté à Claude Code. Si tu n'utilises que Codex, ignore ceci — les limites Codex s'affichent séparément.")
        }
        return t("Claude 한도 조회 실패 (\(status)).", "Failed to fetch Claude limits (\(status)).", "Claude の上限取得に失敗しました (\(status))。", "No se pudieron obtener los límites de Claude (\(status)).", "Échec de récupération des limites Claude (\(status)).")
    }
    var limitRefreshNoCredential: String {
        t("Claude 자격증명을 찾지 못했어요. Claude Code 에 로그인하면 한도가 표시됩니다. Codex만 쓴다면 무시해도 돼요.",
          "No Claude credential found. Sign in to Claude Code to see limits. If you only use Codex you can ignore this.",
          "Claude の認証情報が見つかりません。Claude Code にサインインすると上限が表示されます。Codex のみなら無視して構いません。",
          "No se encontró ninguna credencial de Claude. Inicia sesión en Claude Code para ver los límites. Si solo usas Codex, puedes ignorar esto.",
          "Aucun identifiant Claude trouvé. Connecte-toi à Claude Code pour voir les limites. Si tu n'utilises que Codex, ignore ceci.")
    }
    var limitRefreshReauthNeeded: String {
        t("Claude 자격증명에 계정 로그인 정보가 없어요. Claude Code 에서 `/login` 으로 다시 로그인하면 한도가 표시됩니다.",
          "Your Claude credential has no account sign-in. Run `/login` in Claude Code to sign in again and limits will appear.",
          "Claude の認証情報にアカウントのサインインが含まれていません。Claude Code で `/login` を実行して再度サインインすると上限が表示されます。",
          "Tu credencial de Claude no tiene una sesión de cuenta asociada. Ejecuta `/login` en Claude Code para volver a iniciar sesión y ver los límites.",
          "Ton identifiant Claude n'a pas de connexion de compte. Lance `/login` dans Claude Code pour te reconnecter et les limites apparaîtront.")
    }
    var limitRefreshGeneric: String {
        t("Claude 한도 조회에 실패했어요. 잠시 후 다시 시도하세요.",
          "Couldn't fetch Claude limits. Please try again shortly.",
          "Claude の上限取得に失敗しました。しばらくして再試行してください。",
          "No se pudieron obtener los límites de Claude. Inténtalo de nuevo en unos momentos.",
          "Impossible de récupérer les limites Claude. Réessaie dans un instant.")
    }
    var limitRefreshRateLimited: String {
        t("Claude 한도 조회가 일시 제한됐어요 (429). 잠시 쉬었다가 자동으로 재시도합니다.",
          "Claude limit checks are temporarily rate-limited (429). Backing off and retrying automatically.",
          "Claude の上限取得が一時的に制限されています (429)。少し待って自動的に再試行します。",
          "Las comprobaciones de límites de Claude están temporalmente limitadas (429). Se reintentará automáticamente en breve.",
          "Les vérifications de limites Claude sont temporairement restreintes (429). Pause puis nouvelle tentative automatique.")
    }

    // MARK: Claude 세션 만료(401) 안내
    var claudeAuthExpiredTitle: String {
        t("Claude 세션 만료 — 한도가 갱신 안 돼요",
          "Claude session expired — limits can't refresh",
          "Claude セッション期限切れ — 上限を更新できません",
          "Sesión de Claude expirada — los límites no se pueden actualizar",
          "Session Claude expirée — les limites ne s'actualisent pas")
    }
    var claudeAuthExpiredHint: String {
        t("표시된 값은 만료 전 기준이에요. 다시 시도하거나, Claude Code 를 한 번 실행하면 자동 갱신됩니다.",
          "Values shown are from before expiry. Retry, or run Claude Code once to refresh automatically.",
          "表示値は期限切れ前のものです。再試行するか、Claude Code を一度実行すると自動更新されます。",
          "Los valores mostrados son de antes de la expiración. Reinténtalo, o ejecuta Claude Code una vez para actualizarlos automáticamente.",
          "Les valeurs affichées datent d'avant l'expiration. Réessaie, ou lance Claude Code une fois pour actualiser automatiquement.")
    }
    var retry: String { t("다시 시도", "Retry", "再試行", "Reintentar", "Réessayer") }

    // MARK: 업데이트 알림
    func updateAvailable(_ version: String, current: String) -> String {
        t("🆕 v\(version) 사용 가능 (현재 \(current))",
          "🆕 v\(version) available (you have \(current))",
          "🆕 v\(version) が利用可能（現在 \(current)）",
          "🆕 v\(version) disponible (tienes \(current))",
          "🆕 v\(version) disponible (tu as \(current))")
    }
    var updateButton: String { t("업데이트 방법", "How to update", "更新方法", "Cómo actualizar") }
    var updateHowToTitle: String { t("소스에서 다시 빌드", "Rebuild from source", "ソースから再ビルド", "Reconstruir desde el código") }
    var updateHowToBody: String { t("이 포크는 바이너리를 배포하지 않습니다(Apple 공증 없이 내려받은 앱은 Gatekeeper 가 막습니다). 아래를 실행해 업데이트하세요.", "This fork ships no binaries — without Apple notarisation a downloaded build is blocked by Gatekeeper. Run these to update.", "このフォークはバイナリを配布しません（Apple の公証がないダウンロード版は Gatekeeper に阻まれます）。以下を実行して更新してください。", "Este fork no distribuye binarios — sin la certificación de Apple, una descarga queda bloqueada por Gatekeeper. Ejecuta esto para actualizar.") }
    var updateCopyCommands: String { t("명령 복사", "Copy commands", "コマンドをコピー", "Copiar comandos") }
    var updateReleaseNotes: String { t("릴리스 노트", "Release notes", "リリースノート", "Notas de la versión") }
    var updateLater: String { t("나중에", "Later", "後で", "Más tarde", "Plus tard") }
    var updating: String { t("업데이트 중…", "Updating…", "更新中…", "Actualizando…", "Mise à jour…") }
    var updateSectionTitle: String { t("업데이트", "Updates", "アップデート", "Actualizaciones", "Mises à jour") }
    var updateNotificationsLabel: String { t("업데이트 알림", "Update notifications", "アップデート通知", "Notificaciones de actualización", "Notifications de mise à jour") }
    var checkForUpdatesLabel: String { t("업데이트 확인", "Check for updates", "アップデートを確認", "Buscar actualizaciones", "Rechercher des mises à jour") }
    var checkNowButton: String { t("지금 확인", "Check now", "今すぐ確認", "Comprobar ahora", "Vérifier maintenant") }
    func updateFound(_ version: String) -> String { t("새 버전 v\(version) 있어요", "Version \(version) is available", "バージョン \(version) が利用可能です", "La versión \(version) está disponible", "La version \(version) est disponible") }
    func upToDate(_ version: String) -> String { t("최신 버전이에요 (v\(version))", "You're on the latest (v\(version))", "最新です (v\(version))", "Tienes la última versión (v\(version))", "Tu as la dernière version (v\(version))") }

    // MARK: 알림
    var notifCritical: String { t("한도 임박", "Limit imminent", "上限切迫", "Límite inminente", "Limite imminente") }
    var notifWarning: String { t("한도 경고", "Limit warning", "上限警告", "Aviso de límite", "Alerte de limite") }
    func notifBody(_ name: String, _ percent: String) -> String {
        t("\(name) 한도 \(percent) 사용", "\(name) at \(percent)", "\(name) 上限 \(percent) 使用", "\(name) al \(percent)", "\(name) à \(percent)")
    }
    var claudeFiveHour: String { t("Claude 5시간 세션", "Claude 5-hour session", "Claude 5時間セッション", "Sesión de 5 horas de Claude", "Session de 5 h de Claude") }
    var claudeWeekly: String { t("Claude 주간", "Claude weekly", "Claude 週間", "Semanal de Claude", "Claude hebdo") }
    var codexPersonalLimit: String { t("Codex 개인 한도", "Codex personal limit", "Codex 個人上限", "Límite personal de Codex", "Limite personnelle Codex") }

    // MARK: 가방 / 아이템
    var bag: String { t("가방", "Bag", "バッグ", "Bolsa", "Sac") }
    var bagEmptyTitle: String { t("아직 가방이 비어있어요!", "Your bag is empty!", "バッグはまだ空っぽです！", "¡Tu bolsa todavía está vacía!", "Ton sac est encore vide !") }
    var useItem: String { t("사용하기", "Use", "つかう", "Usar", "Utiliser") }
    var use: String { t("사용", "Use", "つかう", "Usar", "Utiliser") }
    var cancel: String { t("취소", "Cancel", "キャンセル", "Cancelar", "Annuler") }
    func useOnCurrent(_ name: String) -> String {
        t("\(name)에게 사용할까요?", "Use on \(name)?", "\(name) に使いますか？", "¿Usar en \(name)?", "Utiliser sur \(name) ?")
    }
    var useAfterHatch: String { t("부화 후 사용할 수 있어요", "Usable after hatching", "孵化後に使えます", "Se puede usar después de eclosionar", "Utilisable après l'éclosion") }
    var useNeedsPokemon: String { t("사용할 포켓몬이 없어요", "No Pokémon to use it on", "使えるポケモンがいません", "No hay ningún Pokémon en quien usarlo") }
    /// 비타민은 대상(먹일 포켓몬)을 골라야 해서 가방이 아니라 PC 상세 화면에서 쓴다 — 가방 카드엔 이 안내만.
    var useFromPcDetail: String { t("PC에서 포켓몬을 골라 먹여요", "Feed it from a Pokémon's PC detail screen", "PCでポケモンを選んで与えます", "Dáselo desde la pantalla de detalle de un Pokémon en el PC") }

    /// 아이템 표시명 — species 처럼 공식 현지명.
    func itemName(_ kind: ItemKind) -> String {
        switch kind {
        case .rareCandy: return t("이상한 사탕", "Rare Candy", "ふしぎなアメ", "Caramelo Raro")
        case .mint:      return t("민트", "Mint", "ミント", "Menta")
        case .shinyCharm: return t("이로치 부적", "Shiny Charm", "ひかるおまもり", "Amuleto Iris")
        // 본가 공식 번역 명칭(PokéAPI /item/{name} names 기준) — species/move 처럼 하드코딩 없이 런타임
        // 조회하고 싶지만, 상점/가방 텍스트는 이 앱에서 상수 6종뿐이라 다른 아이템과 같은 방식을 따른다.
        case .hpUp:    return t("맥스업", "HP Up", "マックスアップ", "Más PS")
        case .protein: return t("타우린", "Protein", "タウリン", "Proteína")
        case .iron:    return t("사포닌", "Iron", "ブロムヘキシン", "Hierro")
        case .calcium: return t("리보플라빈", "Calcium", "リゾチウム", "Calcio")
        case .zinc:    return t("키토산", "Zinc", "キトサン", "Zinc")
        case .carbos:  return t("알칼로이드", "Carbos", "インドメタシン", "Carburante")
        }
    }
    func itemDescription(_ kind: ItemKind) -> String {
        switch kind {
        case .rareCandy:
            let xp = TokenFormatter.compact(RareCandy.xp)   // 상수에서 파생(하드코딩 드리프트 방지)
            return t("현재 포켓몬의 경험치를 \(xp) 올려줘요.",
                     "Raises your Pokémon's EXP by \(xp).",
                     "ポケモンの経験値を\(xp)上げます。",
                     "Aumenta la experiencia de tu Pokémon en \(xp).")
        case .mint:
            return t("현재 포켓몬의 성격을 랜덤으로 바꿔줘요.",
                     "Randomly changes your Pokémon's nature.",
                     "ポケモンのせいかくをランダムに変えます。",
                     "Cambia aleatoriamente la naturaleza de tu Pokémon.")
        case .shinyCharm:
            return t("보유하면 이로치 포켓몬이 태어날 확률이 올라가요.",
                     "While owned, raises the chance of hatching a shiny.",
                     "持っていると色違いが生まれる確率が上がります。",
                     "Mientras lo tengas, aumenta la probabilidad de que nazca un Pokémon variocolor.")
        case .hpUp, .protein, .iron, .calcium, .zinc, .carbos:
            let ev = Vitamin.evGain
            let stat = vitaminStatName(kind)
            return t("PC 상세 화면에서 원하는 포켓몬에게 먹여 \(stat) 노력치(EV)를 \(ev) 올려요.",
                     "Feed it to any Pokémon from its PC detail screen to raise its \(stat) EVs by \(ev).",
                     "PC詳細画面で好きなポケモンに与えて\(stat)の努力値(EV)を\(ev)上げます。",
                     "Dáselo a un Pokémon desde su pantalla de detalle en el PC para subir sus EVs de \(stat) en \(ev).")
        }
    }
    /// itemDescription 에서 쓰는 스탯 이름 — pcStats* 라벨(HP/공격/…)을 그대로 재사용.
    private func vitaminStatName(_ kind: ItemKind) -> String {
        switch kind {
        case .hpUp: return statHP
        case .protein: return statAttack
        case .iron: return statDefense
        case .calcium: return statSpecialAttack
        case .zinc: return statSpecialDefense
        case .carbos: return statSpeed
        default: return ""
        }
    }
    /// 가방 사용 컨트롤의 효과 힌트 — 민트("성격 랜덤 변경", 사탕의 "+XP" 자리).
    var mintEffectHint: String { t("성격 랜덤 변경", "Random nature", "せいかくランダム変更", "Naturaleza aleatoria", "Nature aléatoire") }

    // MARK: 상점 (재화 = 사용한 토큰)
    var shop: String { t("상점", "Shop", "ショップ", "Tienda", "Boutique") }
    var spendableTokens: String { t("쓸 수 있는 토큰", "Spendable tokens", "使えるトークン", "Tokens disponibles", "Tokens disponibles") }
    var shopHint: String { t("사용한 토큰으로 아이템을 살 수 있어요.", "Spend the tokens you've used on items.", "使ったトークンでアイテムを購入できます。", "Usa los tokens que has consumido para comprar objetos.") }
    // 상점 카테고리 — 탭하면 그 그룹으로 들어간다.
    var shopGroupItems: String { t("아이템", "Items", "アイテム", "Objetos") }
    var shopGroupItemsHint: String { t("이상한 사탕 · 민트 · 이로치 부적", "Rare Candy · Mint · Shiny Charm", "ふしぎなアメ・ミント・ひかるおまもり", "Caramelo Raro · Menta · Amuleto Iris") }
    var shopGroupVitamins: String { t("비타민", "Vitamins", "栄養ドリンク", "Vitaminas") }
    var shopGroupVitaminsHint: String { t("노력치(EV)를 올리는 아이템 6종", "6 items that raise EVs", "努力値(EV)を上げるアイテム6種", "6 objetos que suben los EVs") }
    var shopGroupEggs: String { t("알", "Eggs", "タマゴ", "Huevos") }
    var shopGroupEggsHint: String { t("새 알로 부화를 다시 시작해요", "Start hatching a new egg", "新しいタマゴで孵化をやり直します", "Empieza a eclosionar un huevo nuevo") }
    var buy: String { t("구매", "Buy", "購入", "Comprar", "Acheter") }
    func buyConfirm(_ name: String) -> String { t("\(name) 구매할까요?", "Buy \(name)?", "\(name) を購入しますか？", "¿Comprar \(name)?", "Acheter \(name) ?") }
    var notEnoughTokens: String { t("토큰이 부족해요", "Not enough tokens", "トークンが足りません", "No tienes suficientes tokens", "Pas assez de tokens") }
    func ownedCount(_ n: Int) -> String { t("보유 ×\(n)", "Owned ×\(n)", "所持 ×\(n)", "En posesión ×\(n)", "Possédés ×\(n)") }
    var shopPriceLabel: String { t("가격", "Price", "価格", "Precio", "Prix") }
    var ownedAlready: String { t("보유 중", "Owned", "所持済み", "En posesión", "Possédé") }
    var shinyCharmEffectHint: String { t("이로치 확률 ↑ · 적용 중", "Shiny rate ↑ · active", "色違い率↑ · 適用中", "Prob. variocolor ↑ · activo") }
    // 지역 필터 — 알 후보 풀을 한 세대로 제한(즉시 적용되는 상시 선호도, eggTier 처럼 구매 소비 아님).
    var eggRegionLabel: String { t("지역", "Region", "地方", "Región") }
    var eggRegionAll: String { t("전체", "All", "すべて", "Todas") }
    /// 상한(하나/5세대)이 스프라이트 지원 범위 때문이라는 걸 고르는 순간 알려준다 — 빠진 선택지로
    /// 나중에 발견하게 두지 않는다.
    var eggRegionHint: String {
        t("알 후보를 한 지역으로 좁혀요. 하나(5세대)까지만 지원돼요 — 애니메이션 스프라이트가 거기까지만 있어요.",
          "Narrows which Pokémon can hatch to one region. Supports up to Unova (Gen 5) — that's as far as the animated sprites go.",
          "孵化候補を1つの地方に絞ります。イッシュ(第5世代)まで対応 — アニメーションスプライトの範囲までです。",
          "Limita qué Pokémon pueden nacer a una sola región. Compatible hasta Teselia (Gen 5) — hasta donde llegan los sprites animados.")
    }
    func regionLabel(_ r: Region) -> String {
        switch r {
        case .kanto:  return t("관동", "Kanto", "カントー", "Kanto")
        case .johto:  return t("성도", "Johto", "ジョウト", "Johto")
        case .hoenn:  return t("호연", "Hoenn", "ホウエン", "Hoenn")
        case .sinnoh: return t("신오", "Sinnoh", "シンオウ", "Sinnoh")
        case .unova:  return t("하나", "Unova", "イッシュ", "Teselia")
        }
    }
    // 알 (리롤) — tier = 보증 등급 하한(nil = 보증 없는 기본 알).
    // 이름은 `rarityLabel(r) + " 알"` 식 조합으로 만들지 않는다: 한국어·영어는 맞아떨어져도 일본어에서
    // 조사가 어긋난다(レアのタマゴ vs 자연스러운 レアなタマゴ). 세 언어를 명시 트리플로 적는다.
    func eggName(_ tier: Rarity?) -> String {
        switch tier {
        case nil, .common?: return t("포켓몬 알", "Pokémon Egg", "ポケモンのタマゴ", "Huevo Pokémon", "Œuf Pokémon")
        case .uncommon?:  return t("고급 알", "Uncommon Egg", "アンコモンのタマゴ", "Huevo poco común", "Œuf peu commun")
        case .rare?:      return t("희귀 알", "Rare Egg", "レアのタマゴ", "Huevo raro", "Œuf rare")
        case .legendary?: return t("전설 알", "Legendary Egg", "でんせつのタマゴ", "Huevo legendario", "Œuf légendaire")   // 미판매(FreshEgg.shopTiers)
        }
    }
    func eggDescription(_ tier: Rarity?) -> String {
        guard let tier, tier != .common else {
            return t("지금 포켓몬은 PC로 보내고 새 알의 부화를 시작해요.",
                     "Move your current Pokémon to your PC and start trying to hatch a new one.",
                     "いまのポケモンをPCに送って、新しいタマゴの孵化を始めます。",
                     "Mueve tu Pokémon actual al PC y empieza a intentar eclosionar uno nuevo.")
        }
        let r = rarityLabel(tier)
        return t("지금 포켓몬은 PC로 보내고 \(r) 이상이 확정인 알의 부화를 시작해요.",
                 "Move your current Pokémon to your PC and start trying to hatch one guaranteed \(r) or better.",
                 "いまのポケモンをPCに送って、\(r) 以上が確定のタマゴの孵化を始めます。",
                 "Mueve tu Pokémon actual al PC y empieza a intentar eclosionar uno garantizado de \(r) o superior.")
    }
    /// 인큐베이션 중 표시하는 보증 배지 — 어떤 알을 품고 있는지 한 줄로.
    func eggGuaranteeHint(_ tier: Rarity) -> String {
        let r = rarityLabel(tier)
        return t("\(r) 이상 확정", "\(r) or better", "\(r) 以上確定", "\(r) o superior garantizado", "\(r) ou mieux garanti")
    }
    func eggConfirm(_ monName: String, _ eggName: String) -> String {
        t("\(monName)을(를) PC로 보내고 \(eggName)(으)로 바꿀까요? (\(monName)은 잃지 않아요)",
          "Move \(monName) to your PC and start the \(eggName)? (you keep \(monName))",
          "\(monName) をPCに送って \(eggName) にしますか？（\(monName) は失いません）",
          "¿Mover a \(monName) a tu PC y empezar \(eggName)? (conservas a \(monName))")
    }

    // MARK: 사탕 획득 알림 ("왜 받는지" = 토큰 한도를 다 채운 수고에 대한 보상)
    func notifCandyTitle(item: String, count: Int) -> String {
        t("🍬 \(item) \(count)개를 받았어요!",
          "🍬 You got \(count)× \(item)!",
          "🍬 \(item)を\(count)個もらいました！",
          "🍬 ¡Has recibido \(count)× \(item)!",
          "🍬 Tu as reçu \(count)× \(item) !")
    }
    func notifCandyBody(window: String) -> String {
        t("\(window) 토큰 한도를 다 채웠어요. 열심히 쓴 만큼 사탕을 드려요 — 포켓몬에게 써서 진화시켜 보세요!",
          "You maxed out your \(window) token limit. A treat for the effort — use it to evolve your Pokémon!",
          "\(window)のトークン上限を使い切りました。がんばったごほうびです — ポケモンに使って進化させよう！",
          "Has agotado tu límite de tokens \(window). Un premio por el esfuerzo — ¡úsalo para evolucionar a tu Pokémon!",
          "Tu as atteint ta limite de tokens \(window). Une récompense pour l'effort — utilise-la pour faire évoluer ton Pokémon !")
    }
}
