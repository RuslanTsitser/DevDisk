# Реализуемость системной диагностики в DevDisk

Дата исследования: 14 августа 2026 года.

Целевая конфигурация приложения: macOS 14+, Swift 6, Mac App Store, включённый App Sandbox с `com.apple.security.files.user-selected.read-write`. Воспроизводимый probe запускался на arm64, macOS 26.5.2 (25F84), SDK macOS 26.5.

## Короткий вывод

**Вывод.** Полный запрошенный набор нельзя честно реализовать в текущей sandboxed Mac App Store-сборке.

| Возможность | Текущая MAS-сборка | Direct distribution без App Sandbox |
| --- | --- | --- |
| Общая загрузка CPU | **Проверено: да** | **Проверено: да** |
| CPU по чужим процессам | **Проверено: нет** | **Проверено: частично** — доступно для большинства, но не всех защищённых процессов |
| Общая RAM и memory pressure | **Проверено: да** | **Проверено: да** |
| RAM по чужим процессам | **Проверено: нет** | **Проверено: частично** — доступно для большинства, но не всех защищённых процессов |
| Общий трафик по интерфейсам | **Проверено: да** | **Проверено: да** |
| Трафик по приложениям | **Проверено: технически да**, но только через Content Filter Network Extension | **Проверено: технически да**, через тот же тип system extension |
| Низкая нагрузка для CPU/RAM-сэмплера | **Проверено: да** для доступных totals; **проверено тестом: да** для direct-build PID-сэмплера | **Проверено тестом: да** |
| Низкая нагрузка Network Extension | **Нужно валидировать прототипом** | **Нужно валидировать прототипом** |

Результаты `libproc` в таблице проверены на macOS 26.5.2. **Вывод для deployment target macOS 14+:** поскольку поддерживаемая актуальная ОС уже блокирует функцию и Apple не документирует sandbox entitlement для межпроцессных resource counters, эту возможность нельзя заявлять как поддерживаемую в MAS-продукте. Поведение на macOS 14 и 15 остаётся **непроверенным** и не меняет этот продуктовый вывод.

**Вывод.** Если обязательны все три таблицы «по процессам», практический путь — отдельная Developer ID/notarized сборка без App Sandbox плюс Network Extension. Если Mac App Store обязателен, реалистичный scope: системные CPU/RAM/network totals, метрики самого DevDisk и сеть по приложениям после отдельного прототипа Network Extension; CPU/RAM чужих процессов нужно исключить из обещаний.

## Минимальные технические примитивы

### CPU

**Проверено.** Общая загрузка получается из разницы cumulative CPU ticks двух последовательных вызовов `host_statistics(..., HOST_CPU_LOAD_INFO, ...)` или `host_processor_info`. Apple публикует [`host_statistics64`](https://developer.apple.com/documentation/kernel/1502863-host_statistics64), [`host_processor_info`](https://developer.apple.com/documentation/kernel/1502854-host_processor_info) и структуру [`host_cpu_load_info_t`](https://developer.apple.com/documentation/kernel/host_cpu_load_info_t). В открытом XNU `host_cpu_load_info` определён как ticks по CPU states.

**Проверено.** Для процесса `proc_pidinfo(..., PROC_PIDTASKINFO, ...)` возвращает cumulative user/system time, resident и virtual bytes. Поля структуры опубликованы в [официальном XNU Apple](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h#L124-L145). Текущий SDK также публично объявляет `proc_listallpids`, `proc_pidinfo` и `proc_pid_rusage` в `/usr/include/libproc.h`.

**Вывод.** CPU% процесса вычисляется как разница `user + system` между двумя сэмплами, делённая на wall-clock interval. Следует заранее выбрать семантику: Activity Monitor-подобная шкала может превышать 100% на многоядерном Mac; нормализованная шкала ограничивается 100%.

### RAM

**Проверено.** Физический объём RAM доступен через [`ProcessInfo.physicalMemory`](https://developer.apple.com/documentation/foundation/processinfo/physicalmemory), а системные VM counters — через `host_statistics64(..., HOST_VM_INFO64, ...)`.

**Проверено.** Для процесса `rusage_info_v4.ri_phys_footprint` и `proc_taskinfo.pti_resident_size` присутствуют в публичных SDK/XNU headers. `physical footprint` ближе к пользовательскому смыслу «сколько памяти занимает приложение», чем virtual size. Поля `rusage` опубликованы в [официальном XNU Apple](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h#L289-L329).

**Проверено.** Apple рекомендует интерпретировать состояние памяти прежде всего через Memory Pressure; она зависит не только от free bytes, но также от swap rate, wired memory и file cache. См. [описание Activity Monitor](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac). События состояния pressure доступны через [`DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`](https://developer.apple.com/documentation/dispatch/dispatch_source_type_memorypressure).

**Вывод.** В UI нужно показывать Physical Memory, Memory Used/Available с явно документированной формулой, Compressed, Swap и Memory Pressure. Сумма footprints процессов не обязана совпадать с системным Memory Used из-за shared pages, kernel memory и кэшей.

### Сеть

**Проверено.** Общие cumulative RX/TX counters интерфейса доступны через `getifaddrs` + `if_data.ifi_ibytes/ifi_obytes`; Apple документирует [`if_data`](https://developer.apple.com/documentation/kernel/if_data) и [`ifi_ibytes`](https://developer.apple.com/documentation/kernel/if_data/1492587-ifi_ibytes). Скорость получается из разницы counters между сэмплами.

**Проверено.** Публичный process `rusage` не содержит сетевых byte counters: в SDK 26.5 `rusage_info_v0...v6` есть CPU, memory и disk I/O, но нет network RX/TX. Поэтому соседние `libproc`-возможности нельзя считать решением сетевой атрибуции.

**Проверено.** Официальный механизм атрибуции сетевого flow к приложению — Content Filter Network Extension:

- [`NEFilterFlow`](https://developer.apple.com/documentation/networkextension/nefilterflow) содержит `sourceAppIdentifier`, `sourceAppAuditToken` и `sourceProcessAuditToken`;
- [`NEFilterReport`](https://developer.apple.com/documentation/networkextension/nefilterreport) содержит inbound/outbound byte counts;
- [`statisticsReportFrequency`](https://developer.apple.com/documentation/networkextension/nefilternewflowverdict/statisticsreportfrequency) включает периодические statistics reports;
- официальные частоты: low ≈ 5 с, medium ≈ 1 с, high ≈ 0,5 с — см. [`NEFilterReport.Frequency`](https://developer.apple.com/documentation/networkextension/nefilterreport/frequency);
- macOS content filter упаковывается как system extension и поддерживает App Store и Developer ID distribution согласно [TN3134](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment);
- активация system extension может потребовать явного согласия пользователя: [`requestNeedsUserApproval`](https://developer.apple.com/documentation/systemextensions/ossystemextensionrequestdelegate/requestneedsuserapproval%28_%3A%29).

**Вывод.** На уровне приложения, а не гарантированно каждого PID, можно вернуть `allow` для flow, запросить statistics reports раз в секунду и агрегировать byte deltas по source app. Это не требует чтения payload для самой диагностики.

**Нужно валидировать.** Нельзя до прототипа обещать 100% покрытие процессов и протоколов, корректность под VPN/Private Relay, наличие app identifier для каждого системного flow, фактическое энергопотребление, а также прохождение App Review именно с диагностическим use case. Optional identifiers требуют отдельного bucket `Unattributed`.

## Что показал sandbox-тест

Probe находится в [`Research/SystemDiagnosticsProbe.swift`](../Research/SystemDiagnosticsProbe.swift). Он собран дважды из одного кода: обычным executable и настоящим `.app`, ad-hoc signed с entitlement-файлом DevDisk, запущенным через Launch Services.

### Без App Sandbox

**Проверено тестом.** В одном запуске:

- найдено 185 PID;
- `proc_pidinfo(PROC_PIDTASKINFO)` и `proc_pid_rusage` успешно прочитали 147 чужих процессов;
- часть защищённых процессов вернула `EPERM`.

### С App Sandbox DevDisk

**Проверено тестом.** В том же окружении:

- `proc_listallpids` вернул 0;
- запрос PID 1 через `proc_pidinfo` и `proc_pid_rusage` вернул `EPERM`;
- метрики самого probe читались успешно;
- `host_statistics(HOST_CPU_LOAD_INFO)` и `host_statistics64(HOST_VM_INFO64)` вернули success;
- `getifaddrs` успешно вернул interface byte counters.

**Вывод.** File picker, security-scoped bookmark и Full Disk Access не являются недостающим примитивом: блокируется межпроцессная диагностика, а не чтение выбранных файлов. App Sandbox создаёт барьер в том числе между приложением и другими процессами; Apple описывает этот security boundary в [настройке macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox).

## Замер нагрузки CPU/RAM-сэмплера

Команда воспроизведения для optimized direct executable:

```sh
xcrun swiftc -O -module-cache-path /private/tmp/devdisk-swift-module-cache \
  Research/SystemDiagnosticsProbe.swift \
  -o /private/tmp/devdisk-system-diagnostics-benchmark
/private/tmp/devdisk-system-diagnostics-benchmark --benchmark
```

**Проверено тестом.** 1 000 полных проходов `proc_listallpids + proc_pidinfo + proc_pid_rusage` по примерно 149 доступным процессам заняли 210,978 мс process CPU, или 0,211 мс на проход.

**Вывод.** При частоте 1 Гц один такой сборщик теоретически расходует около 0,021% одного CPU core только на syscalls и агрегацию probe. Это не включает SwiftUI diffing, графики, сортировку, иконки и Network Extension.

**Нужно валидировать.** Production acceptance criteria должны измеряться на минимально поддерживаемом Intel Mac и Apple silicon Mac, с 500+ процессами, включённым Network Extension, открытым и скрытым окном, а также при VPN. Один локальный microbenchmark не доказывает общий energy impact.

## Рекомендуемая архитектура с ограничением нагрузки

### Общий collector

**Вывод.** Один `SystemDiagnosticsService`/actor вне MainActor должен снимать один immutable snapshot для всех экранов. Нельзя создавать timer на строку процесса.

**Вывод.** Базовая частота — 1 Гц. Для графиков это визуально real-time, совпадает с `NEFilterReportFrequencyMedium` и не создаёт бессмысленную частоту UI invalidation. Опциональный режим 0,5 с возможен для foreground diagnostics screen, но требует energy-теста.

**Вывод.** Хранить только фиксированный ring buffer, например 5 минут × 1 sample/s. Сортировать top-N на background actor, публиковать один snapshot на MainActor, не анимировать каждую ячейку, при закрытом diagnostics screen снижать частоту до 5 с или останавливать детальную выборку.

**Вывод.** PID нужно идентифицировать не только числом, но и start time/UUID, потому что PID переиспользуются. Отрицательные deltas после counter reset или interface recreation нужно отбрасывать.

### Вариант A — сохранить Mac App Store

**Проверено:** можно реализовать system CPU, system RAM/pressure, network by interface, self metrics.

**Проверено:** network by app технически возможен через отдельный Content Filter system extension.

**Проверено:** CPU/RAM по чужим процессам невозможны с текущим App Sandbox, согласно воспроизводимому тесту.

**Рекомендация:** если MAS обязателен, изменить продуктовый scope и прямо подписать таблицы как System Overview, Network by App и DevDisk Self Impact. Не имитировать отсутствующие process metrics через `ps`, `top` или private `NetworkStatistics.framework`.

### Вариант B — полный diagnostics build

**Проверено:** direct executable без App Sandbox получает CPU/RAM большинства процессов публичными `libproc`/Mach API.

**Проверено:** сеть по приложениям может поставляться Network Extension system extension вместе с Developer ID-signed приложением.

**Вывод:** это единственная найденная архитектура, близкая ко всему исходному scope. Она требует отдельной Developer ID/notarized distribution, пользовательского разрешения system extension и bucket для недоступных/защищённых процессов.

**Нужно валидировать:** продуктовая приемлемость ухода из MAS или поддержки двух каналов обновления, review/entitlement flow Network Extension, coverage системных процессов и полный performance budget.

## Acceptance criteria для bounded prototype

1. **Проверка возможностей:** никаких private frameworks, парсинга `top/nettop` и недокументированных entitlement’ов.
2. **Частота:** snapshot CPU/RAM и app network stats каждые 1 000 ± 200 мс при открытом diagnostics screen.
3. **Нагрузка:** median < 0,5% одного core и p95 < 1% для collector без UI; весь DevDisk < 1% CPU в idle diagnostics view после стабилизации. Эти пороги — **предлагаемые, нужно согласовать и измерить**, а не уже доказанный результат.
4. **Память:** фиксированный history buffer; рост resident memory < 10 MB после 30 минут. Порог — **предлагаемый, нужно измерить**.
5. **Покрытие:** отдельные `Protected/Unavailable` и `Unattributed` buckets; UI никогда не выдаёт недоступное за ноль.
6. **Сеть:** тесты TCP, UDP, QUIC, long-lived connection, VPN on/off, sleep/wake, interface switch; отсутствие блокировки/задержки пользовательского трафика.
7. **Lifecycle:** подробный polling останавливается при закрытии экрана; counters корректно переживают PID reuse и reset интерфейса.
8. **Privacy:** никакой payload, URL или hostname не сохраняется; только app identity и byte counters. Политика privacy должна быть обновлена до релиза Network Extension.

## Решение, которое нужно принять до реализации

1. Mac App Store обязателен — тогда исключить CPU/RAM по чужим процессам и делать bounded Network Extension prototype.
2. Полный исходный scope обязателен — тогда проектировать отдельную Developer ID/notarized сборку без App Sandbox и параллельно прототипировать Network Extension.

Пытаться реализовать все требования в текущей MAS-сборке без изменения scope технически необоснованно.
