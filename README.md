# Noob to Pro Obby

İngilisdilli Roblox YouTube kanalı üçün obby oyunu. Oyunda 24 mərhələ var və onlar 4 çətinlik səviyyəsinə bölünüb:
**NOOB → ROOKIE → PRO → LEGEND**. Oyunçu lavaya toxunmadan zirvəyə çatmalıdır.

Oyun kanal üçün hazırlanmış video ideyaları əsasında qurulub:

| Video ideyası | Oyunda nə ona xidmət edir |
|---|---|
| #5 "I Made My First Roblox Game in 7 Days" | Bu repo həmin oyundur. Devlog seriyası onun üzərində çəkilə bilər |
| #1 "Noob to Pro" | Səviyyələr NOOB-dan LEGEND-ə qədər çətinləşir |
| #2 "1 Hour to Beat… (Every Fail = New Rule)" | Ekranda taymer, ən yaxşı vaxt və **FALLS** (yıxılma) sayğacı var |
| #15 "Free Player vs Robux Player" | Oyunda heç bir Robux alışı yoxdur, qalib gəlmək yalnız bacarıqdan asılıdır |

## Oyunda nə var

- **24 mərhələ, 8 maneə növü:**
  - `Jumps`: platformadan platformaya tullanmaq
  - `LavaHop`: lava plitələrinin üstündən hoppanmaq
  - `Zigzag`: dar tirlər
  - `Moving`: hərəkət edən platformalar
  - `Vanish`: üstünə basandan sonra yox olan şüşə platformalar
  - `Spinner`: fırlanan lava barı
  - `Conveyor`: geri itələyən lent
  - `Truss`: dırmanmaq
- **Checkpoint-lər:** yıxılan oyunçu son checkpoint-də doğulur. İrəliləyiş DataStore-da saxlanılır, növbəti girişdə oyunçu qaldığı yerdən davam edir.
- **Taymer:** lobbidəki start xəttindən finişə qədər işləyir. Ən yaxşı vaxt yadda saxlanılır.
- **RESTART RUN düyməsi:** oyunu sıfırdan başladır. Təsadüfən basılmasın deyə iki dəfə toxunmaq lazımdır.
- **Leaderboard:** `Stage` və `Wins`.
- Checkpoint-lərə və yeni səviyyəyə çatanda bildiriş çıxır, finişdə konfetti atılır.

## Uşaq təhlükəsizliyi

Oyun 13 yaşdan kiçik auditoriyanı nəzərə alaraq qurulub:

- **Robux alışı yoxdur:** gamepass və developer product yoxdur.
- **Şəxsi məlumat toplanmır:**
  - Yalnız irəliləyiş saxlanılır (checkpoint, qələbə sayı, ən yaxşı vaxt) və bu, `UserId`-ə bağlıdır.
  - `SetAsync`-ə `userIds` ötürülür ki, məlumat silmə (GDPR) sorğularına cavab vermək mümkün olsun.
- **Xarici link, Discord və ya sosial şəbəkə çağırışı yoxdur.** Əlavə söhbət sistemi də yoxdur, Roblox-un standart chat-i işləyir.
- **Qan və qorxu elementi yoxdur.** "Ölüm" cizgi film üslubunda lavaya toxunmaqdır.

Publikasiyadan əvvəl Creator Hub-da **Experience Questionnaire** anketini dürüst doldurun ki, Roblox oyunun yaş reytinqini düzgün təyin etsin.

## Studio-da açmaq

Alətlər [Rokit](https://github.com/rojo-rbx/rokit) ilə qurulur. Versiyalar `rokit.toml` faylındadır.

```bash
rokit install
```

**Variant A: place faylı yaratmaq (ən sadəsi)**

```bash
rojo build default.project.json -o build/NoobToProObby.rbxlx
```

`build/NoobToProObby.rbxlx` faylını Roblox Studio-da açın, sonra **File → Publish to Roblox** seçin.

**Variant B: canlı sinxronizasiya (kodu redaktorda dəyişəndə)**

```bash
rojo serve
```

Studio-da Rojo plagini ilə **Connect** düyməsinə basın.

### Studio-da irəliləyişi yadda saxlamaq

DataStore yalnız publikasiya olunmuş oyunda işləyir. Studio-da test etmək üçün oyunu bir dəfə publikasiya edin, sonra **Game Settings → Security → Enable Studio Access to API Services** seçimini aktiv edin.

Bu seçim aktiv deyilsə, oyun yenə işləyir, sadəcə HUD-da **NOT SAVING** yazısı görünür. Bu normaldır.

## Kursu dəyişmək

- **Mərhələlərin sırası və səviyyələr:** `src/shared/Config.luau` faylında. Hər səviyyə öz mərhələlərini sıra ilə sadalayır.
- **Maneələrin ölçüləri, aralıqları və sürətləri:** `src/server/CourseLayout.luau` faylında.

Dəyişiklikdən sonra `./scripts/check.sh` işə salın. Testlər yoxlayır ki:

- hər tullanma standart personaj üçün mümkündür (aralıq ≤ 8 stud, hündürlük fərqi ≤ 3 stud);
- hər səthin altında lava var;
- hər mərhələnin checkpoint-i var;
- hərəkət edən maneələr ədalətli sürətdədir.

## Layihə strukturu

```
src/
  shared/              (ReplicatedStorage.Shared: server və client birlikdə istifadə edir)
    Config.luau        səviyyələr, mərhələlər, ümumi parametrlər
    TimeFormat.luau    taymer formatı (MM:SS.cc)
  server/              (ServerScriptService.Server)
    Main.server.luau   giriş nöqtəsi
    CourseLayout.luau  kursun planı: hissələrin ölçü və mövqeləri (təmiz data)
    CourseBuilder.luau plandan Workspace-də hissələri qurur
    Mechanics.luau     lava, hərəkətli/yox olan platformalar, spinner, konveyer
    PlayerData.luau    DataStore ilə yükləmə və yadda saxlama
    Progress.luau      checkpoint, respawn, taymer, restart
  client/              (StarterPlayerScripts.Client)
    Hud.client.luau    ekrandakı panel, bildirişlər, restart düyməsi
tests/run.luau         Lune testləri
scripts/check.sh       bütün yoxlamalar
```

## Yoxlamalar

```bash
./scripts/check.sh
```

Skript bunları işə salır:

1. **StyLua:** kod formatını yoxlayır.
2. **Lune testləri:** kurs planını və builder-i Roblox-un instance modeli üzərində yoxlayır. Bu, səhv property adlarını dərhal tutur.
3. **Rojo build:** place faylını yaradır.
4. **luau-lsp:** `--!strict` rejimində Roblox API tipləri ilə tip yoxlaması aparır.
