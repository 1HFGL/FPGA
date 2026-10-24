# 自动轻效果：Delay＋Chorus＋Reverb

接HDMI屏烧录 hdmi_delay_chorus_j13.fs；仅混响对照用 hdmi_reverb_only_reference.fs。
无屏分别使用 piano_delay_chorus_j13.fs / piano_reverb_only_reference.fs。
新版为本轮构建，对照复用上轮已核验文件，具体来源/大小/SHA256见manifest.json和summary.json。

两种乐器均默认自动带效果，无需额外按钮、触摸或上位机设置。
KEY0复位，KEY1中→高→低→中，KEY2钢琴/吉他；双旋钮仍为音量/弯音。
先低音量，试单音、三/四音和弦、快速演奏及两种乐器三个音区。
回声间隔约160ms，轻合唱增加厚度，直达声立即输出。
新版起音比仅混响版约低3dB，比较音色时第二轮可小幅匹配音响响度。
松键等原乐器尾音结束后再等约3秒，不应反复冒出旧音；KEY0应清除旧历史。
详细验收见《试听与设计说明.md》。数字验证/当前约束实现检查通过，尚未替用户烧录或实物验收。
