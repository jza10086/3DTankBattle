# 雷霆战争音效来源

素材文件名与未展开的相对路径以包内 `assets/audio/`为基准。

2026-11-09 从下列作者页面及其下载链接取得素材。所有新增成品位于 `combat/`，均为单声道 32 kHz WAV，已去直流、归一化到约 -2 dBFS，并加入边缘淡化；循环另做交叠。游戏内音量由 `audio/cues/*.tres` 控制。音效经过游戏化处理，不代表真实型号录音。

| 素材 | 作者 | 来源和许可 | 下载原件 |
| --- | --- | --- | --- |
| Light Machine Gun | KuraiWolf | [作者页](https://opengameart.org/content/light-machine-gun)，[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | [lmg_fire01.mp3](https://opengameart.org/sites/default/files/lmg_fire01.mp3) |
| Engine-loop heavy vehicle/tank | Nayckron；原始循环／协作者 qubodup | [作者页](https://opengameart.org/content/engine-loop-heavy-vehicletank)，[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | [engine_heavy_loop_1.ogg](https://opengameart.org/sites/default/files/engine_heavy_loop_1.ogg) |
| Explosions | EZduzziteh | [作者页](https://opengameart.org/content/explosions-4)，[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | [explosion1_0.ogg](https://opengameart.org/sites/default/files/explosion1_0.ogg)、[explosion3.ogg](https://opengameart.org/sites/default/files/explosion3.ogg) |
| Sci-Fi Sounds 1.0 | Kenney | [官网](https://kenney.nl/assets/sci-fi-sounds)、[作者上传页](https://opengameart.org/content/sci-fi-sounds)，[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | [sci-fi_sounds.zip](https://opengameart.org/sites/default/files/sci-fi_sounds.zip) |

CC BY 素材允许商业使用和改编，但发布时须保留作者、来源、许可链接和修改说明。这些信息保存在本文件及 `combat/NOTICE.txt`，Kenney 原包声明保存在 `combat/licenses/Kenney.txt`。原作者未为本游戏背书。

下表文件名省略 `.wav`；Kenney 原文件省略 `.ogg`。涉及机枪原件的混合成品保留 CC BY 4.0 署名，发动机保留 CC BY 3.0 署名，其余下载素材为 CC0。

| 成品与用途 | 原始素材 | 具体加工 |
| --- | --- | --- |
| cannon，穿甲炮击 | explosion1_0、lowFrequency_explosion_000、lmg_fire01 | 爆炸 0.9、低频 0.7、枪声 0.3 混合；低频加速 1.25；最多 2.5 秒 |
| cannon_he，高爆炮击 | explosion1_0、lowFrequency_explosion_000 | 爆炸减速 0.88，低频 0.8 混合；最多 2.8 秒 |
| auto30，30 mm 机炮 | lmg_fire01、explosion3 | 枪声减速 0.65、爆炸层 0.4；最多 0.55 秒 |
| auto25，25 mm 机炮 | lmg_fire01、explosion3 | 枪声减速 0.83、爆炸层 0.25；最多 0.45 秒 |
| machine_gun，同轴机枪 | lmg_fire01 | 截取前 0.38 秒，保留短促枪口声和尾音 |
| ataka，导弹发射 | thrusterFire_000、lmg_fire01 | 推进声叠加 0.1 秒枪口瞬态；最多 1.6 秒 |
| tow，导弹发射 | thrusterFire_000、explosion3 | 推进声减速 0.82，叠加 0.2 秒爆炸；最多 1.8 秒 |
| missile_motor，飞行循环 | thrusterFire_000 | 从 0.25 秒截取 1 秒，80 ms 交叠循环 |
| explosion，炮弹／导弹爆炸 | explosion1_0、explosion3、lowFrequency_explosion_000 | 1 / 0.6 / 0.5 分层，最多 3 秒 |
| wreck，车辆爆毁 | explosion1_0、explosion3、lowFrequency_explosion_000 | 主爆与低频减速 0.8，加碎片层，最多 3.5 秒 |
| armor，装甲受击 | impactMetal_000、explosion3 | 金属减速 0.8，加短促冲击；最多 0.75 秒 |
| ricochet，跳弹 | impactMetal_003 | 加速 1.5，最多 0.65 秒 |
| ground，非爆炸落地 | explosion3 | 截取前 0.45 秒，降低运行时音量 |
| interior_hit，车内受击 | impactMetal_000、lowFrequency_explosion_000 | 金属减速 0.65，加低频闷响；最多 0.55 秒 |
| engine，发动机循环 | engine_heavy_loop_1 | 单声道转换、去直流和 80 ms 交叠，按速度变调 |
| tracks，履带循环 | impactMetal_000、impactMetal_003 | 两种金属声变调交替排列成 2 秒循环；按移动和原地转向调整 |
| traverse，炮塔电机 | engineCircular_002 | 截取 1 秒并交叠，转动时播放 |
| reload，装填机构 | doorClose_000、impactMetal_000 | 门声加速 1.4，加金属层，最多 0.85 秒 |
| ready，装填完成 | doorOpen_000 | 加速 1.5，最多 0.28 秒 |
| alarm，瘫痪／低血量警报 | 本项目原创，CC0 1.0 | 680 / 880 / 680 Hz 三短音，3 秒循环，预留静音间隔 |
| hit_confirm，命中确认 | 本项目原创，CC0 1.0 | 1500 Hz 短衰减音 |
| disable_confirm，瘫痪确认 | 本项目原创，CC0 1.0 | 900 / 1300 Hz 双音 |
| kill_confirm，击杀确认 | 本项目原创，CC0 1.0 | 800 / 1600 Hz 双音 |
| repair，维修完成 | 本项目原创，CC0 1.0 | 660 / 990 Hz 双音 |

原型的 `engine.wav`、`cannon.wav`、`impact.wav` 留在上级目录作为既有原创素材；新的运行时音频场景全部使用 `combat/` 和上述 Cue。
