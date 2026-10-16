-- SPDX-License-Identifier: MIT
--[[-- 访客（原创）。阿页回家时按 chance 依次判定，至多来一位；stay 小时；离开时留 gift 灵感。
  img：assets/visitors/<id>.png --]]
return {
    { id = "inkbug", name = "墨点虫", chance = 0.20, stay = 2, gift = 2,
      arrive = "一只墨点虫顺着书脊爬进来串门。", here = "墨点虫趴在油灯旁，晃着小触角。",
      leave = "墨点虫走了，在桌角留下两点灵感。" },
    { id = "clip_snail", name = "回形针蜗牛", chance = 0.12, stay = 4, gift = 3,
      arrive = "一只回形针蜗牛慢慢挪到了窗台上。", here = "回形针蜗牛在窗台上，壳亮晶晶的。",
      leave = "回形针蜗牛走了，留下一道亮亮的痕迹和三点灵感。" },
    { id = "lampfly", name = "书灯萤", chance = 0.10, stay = 1, gift = 2,
      arrive = "一只书灯萤飞进来，尾巴上的小灯照亮了书桌一角。", here = "书灯萤停在书堆上，灯一明一暗。",
      leave = "书灯萤飞走了，桌上暖暖的，多了两点灵感。" },
    { id = "stamp_turtle", name = "邮票龟", chance = 0.06, stay = 6, gift = 5,
      arrive = "一只背着邮票壳的小乌龟敲了敲门。", here = "邮票龟在藤筐边晒灯光，壳上的齿边一动一动。",
      leave = "邮票龟慢吞吞地走了，壳上的邮票换了一张，留下五点灵感。" },
}
