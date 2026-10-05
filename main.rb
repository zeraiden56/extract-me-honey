# frozen_string_literal: true

require 'ruby2d'
require 'json'
require 'fileutils'
require_relative 'lib/auto_clicker'

WIDTH = 1672
HEIGHT = 941
FIELD_RIGHT = 1168
TOP_HUD = 110
DEMO_MODE = ARGV.include?('--demo')
SMOKE_MODE = ARGV.include?('--smoke')
SAVE_PATH = File.expand_path(ENV.fetch('HONEY_SAVE_PATH', '~/.local/share/extract-me-honey-deluxe/save.json'))
MAX_PERK_LEVEL = 20
CLICK_PASSIVE_SHARE = 0.25
GLOVES_PASSIVE_SHARE = 0.05
OFFLINE_CAP = 8 * 60 * 60
AUTOSAVE_SECONDS = 8

COLORS = {
  sky: '#94c7c9',
  grass: '#72934d',
  grass_dark: '#55713e',
  grass_light: '#8cab5d',
  soil: '#805f3d',
  wood: '#5b3823',
  wood_light: '#835638',
  cream: '#fff3cf',
  ink: '#2c211b',
  honey: '#f7b733',
  honey_light: '#ffd767',
  amber: '#d9871f',
  green: '#476b3d',
  green_light: '#78a65d',
  red: '#b85645',
  blue: '#477d86',
  panel: '#efe0bc',
  panel_dark: '#c9ad79',
  shadow: '#25352c',
  white: '#fffaf0',
  muted: '#75644e',
  pollen: '#e0aa38'
}.freeze

set title: 'Extract Me Honey - Apiario Vivo',
    width: 1280,
    height: 720,
    viewport_width: WIDTH,
    viewport_height: HEIGHT,
    viewport: :letterbox,
    background: COLORS[:sky],
    close_on_esc: true,
    resizable: true

# -------------------------------
# Helpers
# -------------------------------

def clamp(value, minimum, maximum)
  [[value, minimum].max, maximum].min
end

def lerp(a, b, t)
  a + (b - a) * t
end

def format_num(value)
  value = value.to_f
  return '∞' if value.infinite?
  return format('%.2e', value) if value >= 1_000_000_000_000_000
  return format('%.2fT', value / 1_000_000_000_000.0) if value >= 1_000_000_000_000
  return format('%.2fB', value / 1_000_000_000.0) if value >= 1_000_000_000
  return format('%.2fM', value / 1_000_000.0) if value >= 1_000_000
  return format('%.1fK', value / 1_000.0) if value >= 10_000
  return format('%.1f', value) if value < 100 && (value % 1.0).positive?

  value.floor.to_s
end

def point_in_rect?(x, y, rx, ry, rw, rh)
  x >= rx && x <= rx + rw && y >= ry && y <= ry + rh
end

def hive_price(count)
  price = 65 * (1.72**(count - 1))
  price.finite? ? price.ceil : price
end

def bee_price(level)
  (45 * (1.62**level)).ceil
end

def queen_price(level)
  (175 * (1.82**level)).ceil
end

def extractor_price(level)
  (330 * (2.02**level)).ceil
end

def gloves_price(level)
  (30 * (1.58**level)).ceil
end

def cart_price(level)
  (700 * (2.12**level)).ceil
end

def perk_cost(id, level)
  base = {
    'steady_hands' => 1,
    'royal_jelly' => 2,
    'hive_mind' => 3,
    'golden_frames' => 5,
    'second_wind' => 7,
    'legacy_apiary' => 10,
    'rush_capacity' => 5,
    'bee_ai' => 6
  }.fetch(id)
  (base * (1.75**level)).ceil
end

def prestige_requirement(prestige_count)
  25_000 * (1.75**prestige_count)
end

def pollen_from_run(run_honey)
  return 0 if run_honey < 25_000

  Math.sqrt(run_honey / 25_000.0).floor
end

# -------------------------------
# Save data
# -------------------------------

def default_state
  {
    'honey' => 0.0,
    'run_honey' => 0.0,
    'lifetime_honey' => 0.0,
    'hives' => 1,
    'bee_level' => 0,
    'queen_level' => 0,
    'extractor_level' => 0,
    'gloves_level' => 0,
    'cart_level' => 0,
    'pollen' => 0,
    'prestige_count' => 0,
    'perks' => {
      'steady_hands' => 0,
      'royal_jelly' => 0,
      'hive_mind' => 0,
      'golden_frames' => 0,
      'second_wind' => 0,
      'legacy_apiary' => 0,
      'rush_capacity' => 0,
      'bee_ai' => 0
    },
    'saved_at' => Time.now.to_f
  }
end

def sanitize_state(raw)
  base = default_state
  return base unless raw.is_a?(Hash)

  numeric_nonnegative = %w[honey run_honey lifetime_honey]
  numeric_nonnegative.each do |key|
    value = Float(raw.fetch(key, base[key]))
    base[key] = value.finite? && value >= 0 ? value : base[key]
  rescue ArgumentError, TypeError
    next
  end

  integer_nonnegative = %w[bee_level queen_level extractor_level gloves_level cart_level pollen prestige_count]
  integer_nonnegative.each do |key|
    value = Integer(raw.fetch(key, base[key]))
    base[key] = [value, 0].max
  rescue ArgumentError, TypeError
    next
  end

  hives = Integer(raw.fetch('hives', 1)) rescue 1
  base['hives'] = [hives, 1].max

  if raw['perks'].is_a?(Hash)
    base['perks'].keys.each do |key|
      value = Integer(raw['perks'].fetch(key, 0)) rescue 0
      base['perks'][key] = clamp(value, 0, MAX_PERK_LEVEL)
    end
  end

  saved_at = Float(raw.fetch('saved_at', Time.now.to_f)) rescue Time.now.to_f
  base['saved_at'] = saved_at.finite? ? saved_at : Time.now.to_f
  base
end

def load_game
  return default_state unless File.file?(SAVE_PATH)

  sanitize_state(JSON.parse(File.read(SAVE_PATH)))
rescue JSON::ParserError, SystemCallError => error
  warn "Save ignorado: #{error.message}"
  default_state
end

state = (DEMO_MODE || SMOKE_MODE) ? default_state : load_game
if DEMO_MODE
  state.merge!('honey' => 2_400_000.0, 'run_honey' => 2_400_000.0,
               'lifetime_honey' => 2_400_000.0, 'hives' => 12,
               'bee_level' => 1, 'queen_level' => 15, 'extractor_level' => 13,
               'gloves_level' => 4, 'cart_level' => 10)
  state['perks'].merge!('steady_hands' => 2, 'second_wind' => 1,
                        'rush_capacity' => 2, 'bee_ai' => 1)
  state['pollen'] = 25
end

# -------------------------------
# Permanent / production math
# -------------------------------

def perk_level(state, id)
  state.fetch('perks').fetch(id, 0)
end

def permanent_multiplier(state)
  prestige = 1.0 + state.fetch('prestige_count') * 0.08
  golden_frames = 1.0 + perk_level(state, 'golden_frames') * 0.12
  prestige * golden_frames
end

def base_hps(state)
  hive_output = state.fetch('hives') * 1.0
  bees = state.fetch('bee_level') * 2.4
  queens = state.fetch('queen_level') * 10.5
  extractor = 1.0 + state.fetch('extractor_level') * 0.32
  royal = 1.0 + perk_level(state, 'royal_jelly') * 0.08
  hive_mind = 1.0 + perk_level(state, 'hive_mind') * 0.04 * state.fetch('hives')
  cart = 1.0 + state.fetch('cart_level') * 0.20
  (hive_output + bees + queens) * extractor * royal * hive_mind * cart * permanent_multiplier(state)
end

def click_passive_share(state)
  CLICK_PASSIVE_SHARE + state.fetch('gloves_level') * GLOVES_PASSIVE_SHARE
end

def click_honey(state, speed = 1.0)
  gloves = 1 + state.fetch('gloves_level') * 2
  perk = 1.0 + perk_level(state, 'steady_hands') * 0.30
  # base_hps already includes permanent bonuses; apply them only once.
  flat_honey = gloves * permanent_multiplier(state)
  passive_honey = base_hps(state) * click_passive_share(state)
  (flat_honey + passive_honey) * perk * speed
end

def max_rush_speed(state)
  8.0 + perk_level(state, 'rush_capacity') * 2.0
end

def rhythm_speed(state, charge)
  1.0 + clamp(charge, 0.0, 1.0)**1.35 * (max_rush_speed(state) - 1.0)
end

def rhythm_decay(state)
  0.11 * (1.0 - [perk_level(state, 'second_wind') * 0.09, 0.65].min)
end

def rhythm_click_gain(state)
  0.10 + perk_level(state, 'steady_hands') * 0.006
end

def add_honey!(state, amount)
  return if amount <= 0

  state['honey'] += amount
  state['run_honey'] += amount
  state['lifetime_honey'] += amount
end

# Offline earnings use normal speed and are intentionally capped.
offline_seconds = clamp(Time.now.to_f - state.fetch('saved_at'), 0, OFFLINE_CAP)
offline_honey = base_hps(state) * offline_seconds
add_honey!(state, offline_honey)

save_game = lambda do
  next if DEMO_MODE || SMOKE_MODE

  FileUtils.mkdir_p(File.dirname(SAVE_PATH))
  temp = "#{SAVE_PATH}.tmp.#{$$}"
  payload = state.merge('saved_at' => Time.now.to_f)
  File.write(temp, JSON.pretty_generate(payload))
  File.rename(temp, SAVE_PATH)
rescue SystemCallError => error
  warn "Nao foi possivel salvar: #{error.message}"
  File.delete(temp) if defined?(temp) && temp && File.file?(temp)
end

# -------------------------------
# Illustrated scene and live interface
# -------------------------------
require_relative 'lib/honey_art'

Image.new(File.join(HoneyArt::ROOT, 'apiary.png'), width: WIDTH, height: HEIGHT, z: 0)
HoneyArt.icon('mountain', 58, 153, 78, 12)
HoneyArt.text('APIÁRIO VALE DO MEL', 146, 155, 28, '#fff8df', z: 13, bold: true)
world_tip_text = HoneyArt.text('', 146, 195, 16, '#ffdf83', z: 13)
click_tip_text = HoneyArt.text('', 146, 216, 14, '#fff8df', z: 13)

HIVE_POSITIONS = [
  [140, 320], [355, 320], [724, 320], [930, 320],
  [140, 555], [355, 555], [734, 555], [944, 555],
  [140, 701], [350, 701], [733, 701], [941, 701]
].freeze

def visible_hive_count(state)
  [state.fetch('hives'), HIVE_POSITIONS.length].min
end

hive_sprites = HIVE_POSITIONS.each_with_index.map do |(x, y), index|
  shadow = Ellipse.new(x: x + 62, y: y + 104, xradius: 67, yradius: 12, color: '#354a21', opacity: 0.25, z: 9)
  sprite = HoneyArt.sprite('hive', x: x, y: y, width: 124, height: 110, z: 11)
  plaque = HoneyArt.sprite('plaque', x: x + 35, y: y + 98, width: 59, height: 28, z: 12)
  label = HoneyArt.text((index + 1).to_s, x + 35, y + 99, 23, '#fff5d9', z: 13, bold: true)
  label.x += (59 - label.width) / 2
  { x: x, y: y, objects: [shadow, sprite, plaque, label], sprite: sprite, label: label }
end

update_hive_visibility = lambda do
  hive_sprites.each_with_index do |hive, index|
    hive[:objects].each { |object| index < state.fetch('hives') ? object.add : object.remove }
    count = (state.fetch('hives') + HIVE_POSITIONS.length - 1 - index) / HIVE_POSITIONS.length
    hive[:label].content = state.fetch('hives') > HIVE_POSITIONS.length ? "x#{format_num(count)}" : (index + 1).to_s
    HoneyArt.fit(hive[:label], 55, 23)
    hive[:label].x = hive[:x] + 35 + (59 - hive[:label].width) / 2
  end
end
update_hive_visibility.call

keeper = { x: 478.0, y: 606.0, target_x: 478.0, target_y: 606.0,
           timer: 1.2, work_timer: 0.0, dir: -1 }
keeper_shadow = Ellipse.new(x: 478, y: 653, xradius: 25, yradius: 8, color: '#2c4020', opacity: 0.3, z: 18)
keeper_sprite = HoneyArt.sprite('keeper', x: 444, y: 551, width: 70, height: 108, z: 20)
keeper_name = HoneyArt.text('Bento', 454, 527, 22, '#fffad9', z: 24, bold: true)
keeper_sign = HoneyArt.text('Bento cuida daqui', 545, 489, 18, '#fff5d7', z: 14, bold: true, max_width: 117)

move_keeper_sprite = lambda do
  bob = Math.sin(Process.clock_gettime(Process::CLOCK_MONOTONIC) * 9) * 1.4
  keeper_shadow.x, keeper_shadow.y = keeper[:x], keeper[:y] + 46
  keeper_sprite.x, keeper_sprite.y = keeper[:x] - 35, keeper[:y] - 56 + bob
  keeper_sprite.flip = keeper[:dir].positive? ? :horizontal : nil
  keeper_name.x, keeper_name.y = keeper[:x] - 26, keeper[:y] - 83 + bob
end

choose_keeper_target = lambda do
  hx, hy = HIVE_POSITIONS.first(visible_hive_count(state)).sample
  keeper[:target_x] = hx + 126 + rand(-10..10)
  keeper[:target_y] = hy + 61 + rand(-8..8)
  keeper[:dir] = keeper[:target_x] >= keeper[:x] ? 1 : -1
end

# Top bar: only the frame is painted into the background; every value is live.
HoneyArt.icon('comb', 65, 14, 75, 44)
HoneyArt.text('EXTRACT ME HONEY', 150, 19, 40, '#321c0c', z: 45, bold: true, max_width: 303)
HoneyArt.text('EXTRACT ME HONEY', 149, 16, 40, '#ffe185', z: 46, bold: true, max_width: 303)
HoneyArt.text('APIÁRIO VIVO', 152, 60, 26, '#c79050', z: 46, bold: true)

def make_stat_card(x, width, label, icon_id)
  HoneyArt.plate('stat', x, 15, width, 82, 44)
  HoneyArt.icon(icon_id, x + 14, 30, 47, 48)
  HoneyArt.text(label, x + 73, 26, 18, '#dcaf72', z: 49, bold: true)
  HoneyArt.text('0', x + 73, 48, 34, '#fff5de', z: 50, bold: true)
end

honey_text = make_stat_card(475, 183, 'MEL', 'honey')
hps_text = make_stat_card(670, 190, 'POR SEGUNDO', 'bee')
click_text = make_stat_card(873, 155, 'TOQUE', 'hand')
pollen_text = make_stat_card(1042, 193, 'PÓLEN REAL', 'queen')
HoneyArt.plate('rhythm', 1249, 15, 388, 82, 44)
HoneyArt.text('RITMO', 1275, 23, 21, '#fff3d6', z: 50, bold: true)
speed_text = HoneyArt.text('x1.0', 1275, 46, 39, '#ffce4c', z: 50, bold: true)
HoneyArt.plate('progress_track', 1359, 35, 259, 26, 48)
speed_fill = HoneyArt.plate('progress_fill', 1363, 39, 0, 18, 50)
speed_limit_text = HoneyArt.text('', 1485, 17, 15, '#dcaf72', z: 50, bold: true)
rhythm_status = HoneyArt.text('', 1360, 68, 15, '#dabc8e', z: 50)

HoneyArt.icon('house', 1203, 135, 70, 29)
HoneyArt.text('CASA DO APICULTOR', 1288, 138, 34, '#3d220f', z: 30, bold: true, max_width: 330)
shop_tab = GameButton.new(id: 'tab_shop', x: 1200, y: 192, width: 220, height: 71, title: 'LOJA', subtitle: 'crescer agora', kind: :tab)
perk_tab = GameButton.new(id: 'tab_perks', x: 1429, y: 192, width: 210, height: 71, title: 'LEGADO', subtitle: 'renascer + perks', kind: :tab)

shop_buttons = [
  GameButton.new(id: 'hive', x: 1200, y: 274, width: 438, height: 96, title: 'NOVA COLMEIA', subtitle: '+1 base de produção'),
  GameButton.new(id: 'bee', x: 1200, y: 380, width: 438, height: 96, title: 'MAIS ABELHAS', subtitle: '+2.4 mel/s por nível'),
  GameButton.new(id: 'queen', x: 1200, y: 486, width: 438, height: 96, title: 'RAINHA FORTE', subtitle: '+10.5 mel/s por nível'),
  GameButton.new(id: 'extractor', x: 1200, y: 592, width: 438, height: 96, title: 'EXTRATOR', subtitle: '+32% de produção'),
  GameButton.new(id: 'gloves', x: 1200, y: 700, width: 214, height: 118, title: 'LUVAS', subtitle: '+2 e +5% do mel/s'),
  GameButton.new(id: 'cart', x: 1424, y: 700, width: 214, height: 118, title: 'CARROÇA', subtitle: '+20% total')
]
tip_icon = HoneyArt.icon('bulb', 1219, 843, 33, 30)
shop_footer = HoneyArt.text('Colmeias sem limite. Cliques crescem com o mel/s.', 1258, 846, 16, '#65452c', z: 33, max_width: 369)
save_status = HoneyArt.text(DEMO_MODE ? 'demonstração · progresso temporário' : 'salvamento automático', 1258, 881, 16, '#795435', z: 33)

perk_buttons = [
  GameButton.new(id: 'steady_hands', x: 1200, y: 342, width: 214, height: 104, title: 'MÃOS FIRMES', subtitle: '+30% toque / nível', kind: :perk),
  GameButton.new(id: 'royal_jelly', x: 1424, y: 342, width: 214, height: 104, title: 'GELEIA REAL', subtitle: '+8% prod. / nível', kind: :perk),
  GameButton.new(id: 'hive_mind', x: 1200, y: 452, width: 214, height: 104, title: 'MENTE-COLMEIA', subtitle: '+4% por colmeia', kind: :perk),
  GameButton.new(id: 'golden_frames', x: 1424, y: 452, width: 214, height: 104, title: 'FAVOS DOURADOS', subtitle: '+12% permanente', kind: :perk),
  GameButton.new(id: 'second_wind', x: 1200, y: 562, width: 214, height: 104, title: 'SEGUNDO FÔLEGO', subtitle: 'ritmo cai mais lento', kind: :perk),
  GameButton.new(id: 'legacy_apiary', x: 1424, y: 562, width: 214, height: 104, title: 'HERANÇA', subtitle: '+1 colmeia ao renascer', kind: :perk),
  GameButton.new(id: 'rush_capacity', x: 1200, y: 672, width: 214, height: 104, title: 'RITMO MÁXIMO', subtitle: '+2x no teto / nível', kind: :perk),
  GameButton.new(id: 'bee_ai', x: 1424, y: 672, width: 214, height: 104, title: 'AbelhIA', subtitle: '1 clique/s por nível', kind: :perk)
]
perk_connectors = [
  Rectangle.new(x: 1304, y: 443, width: 5, height: 12, color: '#ac8450', z: 29),
  Rectangle.new(x: 1528, y: 443, width: 5, height: 12, color: '#ac8450', z: 29),
  Rectangle.new(x: 1304, y: 553, width: 5, height: 12, color: '#ac8450', z: 29),
  Rectangle.new(x: 1528, y: 553, width: 5, height: 12, color: '#ac8450', z: 29),
  Rectangle.new(x: 1304, y: 663, width: 5, height: 12, color: '#ac8450', z: 29),
  Rectangle.new(x: 1304, y: 668, width: 229, height: 3, color: '#ac8450', z: 29),
  Rectangle.new(x: 1528, y: 668, width: 5, height: 7, color: '#ac8450', z: 29)
]
perk_prerequisites = {
  'steady_hands' => [], 'royal_jelly' => [],
  'hive_mind' => [['royal_jelly', 1]],
  'golden_frames' => [['steady_hands', 1], ['royal_jelly', 1]],
  'second_wind' => [['steady_hands', 2]],
  'legacy_apiary' => [['hive_mind', 2], ['golden_frames', 2]],
  'rush_capacity' => [['second_wind', 1]],
  'bee_ai' => [['second_wind', 1]]
}.freeze
perk_unlocked = lambda do |id|
  perk_prerequisites.fetch(id).all? { |parent, level| perk_level(state, parent) >= level }
end
prestige_title = HoneyArt.text('CULTIVE SEU LEGADO', 1212, 280, 27, COLORS[:ink], z: 33, bold: true)
prestige_info = HoneyArt.text('', 1212, 316, 16, COLORS[:muted], z: 33)
prestige_button = GameButton.new(id: 'prestige', x: 1200, y: 788, width: 438, height: 64, title: 'RENASCER APIÁRIO', subtitle: 'preserva pólen e melhorias')
legacy_info = HoneyArt.text('', 1212, 861, 15, COLORS[:muted], z: 33)
current_tab = 'shop'

set_tab_visibility = lambda do
  shopping = current_tab == 'shop'
  shop_tab.active = shopping
  perk_tab.active = !shopping
  shop_buttons.each { |button| button.visible = shopping }
  perk_buttons.each { |button| button.visible = !shopping }
  perk_connectors.each { |object| shopping ? object.remove : object.add }
  prestige_button.visible = !shopping
  [prestige_title, prestige_info, legacy_info].each { |object| shopping ? object.remove : object.add }
  shopping ? tip_icon.add : tip_icon.remove
  shop_footer.content = shopping ? 'Colmeias sem limite. Cliques crescem com o mel/s.' : ''
end
set_tab_visibility.call

# -------------------------------
# Feedback / game feel
# -------------------------------

floating_texts = []
bees = []
click_bursts = []
message_bg = HoneyArt.plate('toast', 528, 122, 592, 50, 69)
message_bg.remove
message_text = HoneyArt.text('', 548, 135, 21, COLORS[:cream], z: 70, bold: true)
message_timer = 0.0

rush = DEMO_MODE ? 0.79 : 0.0
rush_flash = 0.0
bee_spawn_timer = 0.0
golden_bee = nil
golden_timer = rand(22.0..40.0)
auto_clicker = AutoClicker.new
auto_hive_index = 0
auto_target = HIVE_POSITIONS.first.dup
auto_bee = HoneyArt.icon('bee_ai', 0, 0, 36, 23)
auto_bee.tint = '#c8eeff'
auto_bee.remove
auto_name = HoneyArt.text('AbelhIA', 0, 0, 18, '#d8faff', z: 24, bold: true)
auto_name.remove

spawn_float = lambda do |text, x, y, color = COLORS[:cream], size = 18|
  floating_texts << FloatingText.new(text, x, y, color, size)
end

show_message = lambda do |text, color = COLORS[:cream]|
  message_text.content = text
  message_text.color = color
  HoneyArt.fit(message_text, 548, 21)
  message_text.x = 528 + (592 - message_text.width) / 2
  message_bg.add
  message_timer = 2.4
end

rush_speed = lambda do
  rhythm_speed(state, rush)
end

spawn_click_burst = lambda do |x, y|
  6.times do |i|
    angle = (Math::PI * 2 / 6) * i + rand(-0.25..0.25)
    click_bursts << {
      shape: Circle.new(x: x, y: y, radius: rand(2..5), color: i.even? ? COLORS[:honey] : COLORS[:cream], z: 75),
      vx: Math.cos(angle) * rand(35..80),
      vy: Math.sin(angle) * rand(35..80),
      life: 0.45
    }
  end
end

# Both player input and AbelhIA use the same rewards and rhythm gain.
perform_field_click = lambda do |x, y, count: 1, automatic: false|
  on_hive = hive_sprites.first(visible_hive_count(state)).any? do |hive|
    point_in_rect?(x, y, hive[:x], hive[:y], 124, 110)
  end
  amount = click_honey(state, rush_speed.call) * count * (on_hive ? 1.5 : 1.0)
  add_honey!(state, amount)
  rush = clamp(rush + rhythm_click_gain(state) * count, 0.0, 1.0)
  rush_flash = 0.18
  label = automatic ? "AbelhIA +#{format_num(amount)}" : "+#{format_num(amount)}"
  spawn_float.call(label, x + 6, y - 18, automatic ? '#d8faff' : COLORS[:honey_light], 18)
  spawn_click_burst.call(x, y)
  spawn_float.call('FAVO!', x - 10, y - 38, '#fff19c', 14) if on_hive && !automatic
end

# -------------------------------
# Upgrade logic
# -------------------------------

upgrade_cost = lambda do |id|
  case id
  when 'hive' then hive_price(state.fetch('hives'))
  when 'bee' then bee_price(state.fetch('bee_level'))
  when 'queen' then queen_price(state.fetch('queen_level'))
  when 'extractor' then extractor_price(state.fetch('extractor_level'))
  when 'gloves' then gloves_price(state.fetch('gloves_level'))
  when 'cart' then cart_price(state.fetch('cart_level'))
  else 0
  end
end

buy_upgrade = lambda do |id|
  cost = upgrade_cost.call(id)
  if state.fetch('honey') < cost
    show_message.call("Faltam #{format_num(cost - state.fetch('honey'))} de mel", '#ffd0b2')
    next
  end

  state['honey'] -= cost
  case id
  when 'hive' then state['hives'] += 1
  when 'bee' then state['bee_level'] += 1
  when 'queen' then state['queen_level'] += 1
  when 'extractor' then state['extractor_level'] += 1
  when 'gloves' then state['gloves_level'] += 1
  when 'cart' then state['cart_level'] += 1
  end

  update_hive_visibility.call if id == 'hive'
  rush = clamp(rush + 0.12, 0.0, 1.0)
  show_message.call('Melhoria comprada! A fazenda ficou mais viva.', COLORS[:honey_light])
end

buy_perk = lambda do |id|
  unless perk_unlocked.call(id)
    show_message.call('Esse perk ainda esta bloqueado pela arvore.', '#ffd0b2')
    next
  end

  current = perk_level(state, id)
  if current >= MAX_PERK_LEVEL
    show_message.call('Essa melhoria já está no nível máximo.', '#fff19c')
    next
  end
  cost = perk_cost(id, current)
  if state.fetch('pollen') < cost
    show_message.call("Voce precisa de #{cost - state.fetch('pollen')} polen real", '#ffd0b2')
    next
  end

  state['pollen'] -= cost
  state['perks'][id] = current + 1
  auto_clicker.reset if id == 'bee_ai' && current.zero?
  show_message.call('Perk permanente desbloqueado!', '#e5ffc7')
end

perform_prestige = lambda do
  gain = pollen_from_run(state.fetch('run_honey'))
  requirement = prestige_requirement(state.fetch('prestige_count'))
  if state.fetch('run_honey') < requirement || gain <= 0
    show_message.call("Produza #{format_num(requirement)} nesta vida para renascer", '#ffd0b2')
    next
  end

  state['pollen'] += gain
  state['prestige_count'] += 1
  bonus_hives = 1 + perk_level(state, 'legacy_apiary')
  state['honey'] = 0.0
  state['run_honey'] = 0.0
  state['hives'] = bonus_hives
  state['bee_level'] = 0
  state['queen_level'] = 0
  state['extractor_level'] = 0
  state['gloves_level'] = 0
  state['cart_level'] = 0
  rush = 0.0
  auto_clicker.reset
  auto_hive_index = 0
  auto_target = HIVE_POSITIONS.first
  update_hive_visibility.call
  show_message.call("RENASCIMENTO! +#{gain} polen real", '#fff19c')
  save_game.call
end

# -------------------------------
# Mouse interactions
# -------------------------------

mouse_x = 0
mouse_y = 0

on :mouse_move do |event|
  mouse_x = event.x
  mouse_y = event.y
end

on :mouse_down do |event|
  next unless event.button?(:left)

  mouse_x = event.x
  mouse_y = event.y

  # Tabs are always clickable.
  if shop_tab.contains?(event.x, event.y)
    current_tab = 'shop'
    set_tab_visibility.call
    next
  elsif perk_tab.contains?(event.x, event.y)
    current_tab = 'perks'
    set_tab_visibility.call
    next
  end

  if current_tab == 'shop'
    clicked_button = shop_buttons.find { |button| button.contains?(event.x, event.y) }
    if clicked_button
      buy_upgrade.call(clicked_button.id)
      next
    end
  else
    clicked_perk = perk_buttons.find { |button| button.contains?(event.x, event.y) }
    if clicked_perk
      buy_perk.call(clicked_perk.id)
      next
    end
    if prestige_button.contains?(event.x, event.y)
      perform_prestige.call
      next
    end
  end

  # Golden bee event.
  if golden_bee && point_in_rect?(event.x, event.y, golden_bee[:x] - 30, golden_bee[:y] - 30, 60, 60)
    reward = [base_hps(state) * 20, 35].max
    add_honey!(state, reward)
    spawn_float.call("ABELHA DOURADA +#{format_num(reward)}", event.x - 80, event.y - 28, '#fff19c', 17)
    golden_bee[:objects].each(&:remove)
    golden_bee = nil
    golden_timer = rand(28.0..50.0)
    rush = clamp(rush + 0.28, 0.0, 1.0)
    next
  end

  # Clicking the field is the active mechanic: direct honey + farm speed.
  if event.x.between?(0, FIELD_RIGHT - 1) && event.y.between?(TOP_HUD, HEIGHT)
    perform_field_click.call(event.x, event.y)
  end
end

on :close do
  save_game.call
end

# -------------------------------
# Update loop
# -------------------------------

last_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
last_save = last_time
if SMOKE_MODE
  require_relative 'test/smoke'
  smoke_test = HoneySmoke.new
end

update do
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  elapsed = clamp(now - last_time, 0.0, OFFLINE_CAP)
  dt = clamp(elapsed, 0.0, 0.05)
  last_time = now

  rush = clamp(rush - rhythm_decay(state) * elapsed, 0.0, 1.0)
  rush_flash = [rush_flash - dt, 0.0].max

  # Clock time, never multiplied by rhythm: one automatic pulse per second.
  auto_level = perk_level(state, 'bee_ai')
  auto_clicks = auto_clicker.advance(elapsed, auto_level)
  if auto_clicks.positive?
    auto_target = HIVE_POSITIONS[auto_hive_index % visible_hive_count(state)]
    auto_hive_index += 1
    perform_field_click.call(auto_target[0] + 62, auto_target[1] + 45, count: auto_clicks, automatic: true)
  end
  if auto_level.positive?
    bob = Math.sin(now * 6) * 4
    auto_bee.x, auto_bee.y = auto_target[0] + 105, auto_target[1] - 26 + bob
    auto_name.x, auto_name.y = auto_target[0] + 84, auto_target[1] - 48 + bob
    auto_bee.add
    auto_name.add
  else
    auto_bee.remove
    auto_name.remove
  end
  speed = rush_speed.call

  # Passive economy accelerated by rhythm.
  add_honey!(state, base_hps(state) * speed * dt)

  # Beekeeper AI.
  dx = keeper[:target_x] - keeper[:x]
  dy = keeper[:target_y] - keeper[:y]
  distance = Math.sqrt(dx * dx + dy * dy)
  if distance < 8
    keeper[:timer] -= dt * speed
    if keeper[:timer] <= 0
      keeper[:timer] = rand(0.5..1.6)
      choose_keeper_target.call
    end
  else
    move_speed = (44 + state.fetch('cart_level') * 3) * (0.72 + speed * 0.28)
    keeper[:x] += dx / distance * move_speed * dt
    keeper[:y] += dy / distance * move_speed * dt
    keeper[:dir] = dx >= 0 ? 1 : -1
  end
  move_keeper_sprite.call

  # Bento occasionally "services" a hive, creating a tiny production pulse.
  keeper[:work_timer] += dt * speed
  if keeper[:work_timer] >= 4.5
    keeper[:work_timer] = 0.0
    pulse = [base_hps(state) * 1.2, 2].max
    add_honey!(state, pulse)
    spawn_float.call("Bento +#{format_num(pulse)}", keeper[:x] - 35, keeper[:y] - 95, '#fff0a8', 22)
    keeper_sign.content = "Bento +#{format_num(pulse)}"
    HoneyArt.fit(keeper_sign, 117, 18)
  end

  # Ambient bees scale with progression.
  bee_spawn_timer -= dt * speed
  desired_bees = [2 + state.fetch('hives') + state.fetch('bee_level') / 2, 18].min
  if bee_spawn_timer <= 0 && bees.length < desired_bees
    hx, hy = HIVE_POSITIONS.first(visible_hive_count(state)).sample
    target_x = rand(50..1110)
    target_y = rand(302..808)
    bees << BeeParticle.new(hx + 62, hy + 40, target_x, target_y, 0.8 + rand * 0.7)
    bee_spawn_timer = rand(0.22..0.62)
  end
  bees.each { |bee| bee.update(dt, clamp(speed, 1.0, 3.0)) }
  bees.reject!(&:dead)

  # Golden bee event.
  golden_timer -= dt
  if golden_bee.nil? && golden_timer <= 0
    gx = rand(90..1100)
    gy = rand(310..785)
    glow = Circle.new(x: gx, y: gy, radius: 30, color: '#ffe980', opacity: 0.65, z: 66)
    body = HoneyArt.icon('bee', gx - 24, gy - 24, 48, 67)
    golden_bee = { x: gx, y: gy, life: 8.0, objects: [glow, body] }
    show_message.call('Uma ABELHA DOURADA apareceu no campo!', '#fff19c')
  elsif golden_bee
    golden_bee[:life] -= dt
    if golden_bee[:life] <= 0
      golden_bee[:objects].each(&:remove)
      golden_bee = nil
      golden_timer = rand(26.0..48.0)
    end
  end

  # Floating feedback.
  floating_texts.each { |f| f.update(dt) }
  floating_texts.reject!(&:dead)

  click_bursts.each do |particle|
    particle[:life] -= dt
    particle[:shape].x += particle[:vx] * dt
    particle[:shape].y += particle[:vy] * dt
    particle[:vy] += 95 * dt
    if particle[:life] <= 0
      particle[:shape].remove
      particle[:dead] = true
    end
  end
  click_bursts.reject! { |particle| particle[:dead] }

  # HUD values.
  honey_text.content = format_num(state.fetch('honey'))
  hps_text.content = format_num(base_hps(state) * speed)
  click_text.content = format_num(click_honey(state, speed))
  click_tip_text.content = format('Toque: +%.0f%% mel/s · colmeia x1,5', click_passive_share(state) * 100)
  HoneyArt.fit(click_tip_text, 322, 14)
  pollen_text.content = state.fetch('pollen').to_s
  [[honey_text, 98], [hps_text, 105], [click_text, 72], [pollen_text, 105]].each do |text, width|
    HoneyArt.fit(text, width, 34)
  end
  speed_text.content = format('x%.1f', speed)
  HoneyArt.fit(speed_text, 78, 39)
  speed_limit_text.content = format('MÁX. x%.1f', max_rush_speed(state))
  rhythm_status.content = auto_level.positive? ? "AbelhIA: #{auto_level} clique#{auto_level == 1 ? '' : 's'}/s" : 'cliques mantêm a fazenda acelerada'
  speed_fill.width = 251 * rush
  speed_fill.tint = rush_flash.positive? ? '#fffbe3' : '#ffffff'

  # Hover and button labels.
  shop_tab.hover = shop_tab.contains?(mouse_x, mouse_y)
  perk_tab.hover = perk_tab.contains?(mouse_x, mouse_y)

  shop_buttons.each do |button|
    button.hover = current_tab == 'shop' && button.contains?(mouse_x, mouse_y)
    id = button.id
    button.disabled = false
    cost = upgrade_cost.call(id)
    button.affordable = state.fetch('honey') >= cost
    button.set_cost("#{format_num(cost)} mel")
    count = state.fetch('hives')
    button.set_detail(id == 'hive' ? "#{format_num(count)} #{count == 1 ? 'colmeia' : 'colmeias'} · sem limite" : '')
  end

  if current_tab == 'perks'
    perk_buttons.each do |button|
      unlocked = perk_unlocked.call(button.id)
      level = perk_level(state, button.id)
      maxed = level >= MAX_PERK_LEVEL
      button.disabled = !unlocked || maxed
      button.hover = unlocked && !maxed && button.contains?(mouse_x, mouse_y)
      button.set_level(level)
      if maxed
        button.set_cost('MÁX.')
      elsif unlocked
        cost = perk_cost(button.id, level)
        button.affordable = state.fetch('pollen') >= cost
        button.set_cost("#{cost}")
      else
        button.set_cost('—')
      end
    end

    gain = pollen_from_run(state.fetch('run_honey'))
    requirement = prestige_requirement(state.fetch('prestige_count'))
    prestige_info.content = "Vida atual: #{format_num(state.fetch('run_honey'))} mel | alvo: #{format_num(requirement)}"
    can_prestige = state.fetch('run_honey') >= requirement && gain.positive?
    prestige_button.affordable = can_prestige
    prestige_button.set_cost(gain.positive? ? "+#{gain}" : '0')
    prestige_button.hover = prestige_button.contains?(mouse_x, mouse_y)
    HoneyArt.fit(prestige_info, 416, 16)
    legacy_info.content = "Renascimentos: #{state.fetch('prestige_count')} | bonus global: +#{(state.fetch('prestige_count') * 8)}%"
    hovered_perk = perk_buttons.find { |button| button.contains?(mouse_x, mouse_y) }
    if hovered_perk && !perk_unlocked.call(hovered_perk.id)
      requirements = perk_prerequisites.fetch(hovered_perk.id).map do |id, level|
        title = perk_buttons.find { |button| button.id == id }.title.content.downcase
        "#{title} nv. #{level}"
      end
      legacy_info.content = "Requer: #{requirements.join(' + ')}"
    elsif hovered_perk&.id == 'rush_capacity'
      legacy_info.content = format('Ritmo máximo: x%.1f · +2 por nível', max_rush_speed(state))
    elsif hovered_perk&.id == 'bee_ai'
      legacy_info.content = 'Clica nas colmeias a cada segundo e mantém o ritmo.'
    end
    HoneyArt.fit(legacy_info, 413, 15)
  end

  # Contextual world copy evolves with progress.
  world_tip_text.content = case state.fetch('hives')
                        when 1..3 then 'Clique no campo para ganhar ritmo!'
                        when 4..7 then 'Seu apiário está crescendo!'
                        when 8..12 then 'Bento cuida do mel. Continue crescendo!'
                        else "#{format_num(state.fetch('hives'))} colmeias · #{HIVE_POSITIONS.length} grupos no campo"
                        end
  HoneyArt.fit(world_tip_text, 322, 16)

  # Dismiss transient feedback while keeping the painted scene unobstructed.
  if message_timer.positive?
    message_timer -= dt
    if message_timer <= 0
      message_text.content = ''
      message_bg.remove
    end
  end

  # Autosave.
  if !DEMO_MODE && !SMOKE_MODE && now - last_save >= AUTOSAVE_SECONDS
    save_game.call
    last_save = now
    save_status.content = "salvo #{Time.now.strftime('%H:%M:%S')}"
  end

  smoke_test&.step(binding)
end

if offline_honey >= 1 && !DEMO_MODE && !SMOKE_MODE
  show_message.call("Bem-vindo! +#{format_num(offline_honey)} mel offline", '#fff19c')
end

save_game.call
show
