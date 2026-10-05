# frozen_string_literal: true

# All artwork is project-local. Sprites share one texture; the PNG is never
# sliced or rewritten at runtime. Coordinates use the reference's 1672x941 canvas.
module HoneyArt
  ROOT = File.expand_path('../assets', __dir__)
  FONT = File.join(ROOT, 'fonts/DroidSans.ttf')
  HEADING = File.join(ROOT, 'fonts/LiberationSansNarrow-Bold.ttf')
  ICONS = {
    'honey' => 'jar', 'pollen' => 'queen', 'prestige' => 'queen',
    'tab_shop' => 'shop', 'tab_perks' => 'sprout', 'steady_hands' => 'gloves',
    'royal_jelly' => 'jar', 'hive_mind' => 'bee', 'golden_frames' => 'comb',
    'second_wind' => 'sprout', 'legacy_apiary' => 'hive',
    'rush_capacity' => 'hand', 'bee_ai' => 'bee'
  }.freeze

  def self.sprite(id, x:, y:, width:, height:, z: 35, **options)
    @sheet ||= Ruby2D::SpriteSheet.new(File.join(ROOT, 'sprites.json'))
    frame = ICONS.fetch(id.to_s, id.to_s)
    Ruby2D::Sprite.new(@sheet, frame: frame, x: x, y: y,
                      width: width, height: height, z: z, **options)
  end

  def self.icon(id, x, y, size, z = 35)
    @sheet ||= Ruby2D::SpriteSheet.new(File.join(ROOT, 'sprites.json'))
    frame = @sheet.frame(ICONS.fetch(id.to_s, id.to_s))
    scale = size.to_f / [frame[:width], frame[:height]].max
    w, h = frame[:width] * scale, frame[:height] * scale
    sprite(id, x: x + (size - w) / 2, y: y + (size - h) / 2, width: w, height: h, z: z)
  end

  def self.plate(name, x, y, width, height, z = 30)
    Ruby2D::Image.new(File.join(ROOT, "ui/#{name}.svg"), x: x, y: y,
                      width: width, height: height, z: z)
  end

  def self.text(content, x, y, size = 20, color = '#422611', z: 36, bold: false, max_width: nil)
    text = Ruby2D::Text.new(content, x: x, y: y, size: size, color: color,
                           font: bold ? HEADING : FONT, z: z)
    fit(text, max_width, size) if max_width
    text
  end

  def self.fit(text, width, size)
    key = [text.content, width, size]
    return text if text.instance_variable_get(:@honey_fit_key) == key

    text.size = size
    text.size -= 1 while text.width > width && text.size > 10
    text.instance_variable_set(:@honey_fit_key, key)
    text
  end
end

class GameButton
  attr_reader :x, :y, :width, :height, :id, :title, :cost

  def initialize(id:, x:, y:, width:, height:, title:, subtitle: '', kind: :shop)
    @id, @x, @y, @width, @height, @kind = id, x, y, width, height, kind
    @visible, @affordable, @disabled, @active, @hover = true, true, false, false, false
    @compact = width < 300
    @objects = []
    @bg = HoneyArt.plate(kind == :tab ? 'tab_off' : (@compact ? (kind == :perk ? 'perk' : 'compact') : 'card'), x, y, width, height + 5)
    @objects << @bg
    if kind == :tab
      @selected_bg = HoneyArt.plate('tab_on', x, y, width, height + 5, 31)
      @selected_bg.remove
      @objects << HoneyArt.icon(id, x + 22, y + 15, 43)
      @title = HoneyArt.text(title, x + 83, y + 10, 26, '#fff3d2', bold: true)
      @subtitle = HoneyArt.text(subtitle, x + 83, y + 43, 16, '#f8e4c4', max_width: width - 91)
    else
      small = @compact
      size = small ? 56 : [72, height - 24].min
      @objects << HoneyArt.plate('tile', x + 15, y + 13, size, size, 32)
      @objects << HoneyArt.icon(id, x + 21, y + 19, size - 12)
      tx = x + (small ? 78 : 100)
      text_width = small ? width - 85 : width - 239
      @title = HoneyArt.text(title, tx, y + 12, small ? 22 : 24, '#24180f', bold: true, max_width: text_width)
      @subtitle = HoneyArt.text(subtitle, tx, y + 44, small ? 15 : 17, '#715238', max_width: text_width)
      @detail = HoneyArt.text('', tx, y + 69, 15, '#ab580f', bold: true)
      @objects << @detail
      @cost_x = small ? x + 82 : x + width - 134
      @cost_y = small ? y + height - 45 : y + (height - 62) / 2
      @cost_width = small ? width - 92 : 120
      @cost_height = small ? 36 : 62
      @cost_bg = HoneyArt.plate(small ? 'cost_small' : 'cost', @cost_x, @cost_y, @cost_width, @cost_height + 4, 34)
      @coin = HoneyArt.icon(id == 'prestige' || kind == :perk ? 'pollen' : 'honey', @cost_x + 8, @cost_y + (@cost_height - 25) / 2, 25, 35)
      @cost = HoneyArt.text('', @cost_x + 34, @cost_y, 20, '#32200c', bold: true)
      @objects.concat([@cost_bg, @coin, @cost])
      if kind == :perk
        @level = HoneyArt.text('NV. 0', x + 17, y + height - 32, 15, '#9a6a36', bold: true)
        @objects << @level
      end
    end
    @objects.concat([@title, @subtitle])
  end

  def contains?(mx, my)
    @visible && mx.between?(@x, @x + @width) && my.between?(@y, @y + @height)
  end

  def set_cost(content)
    return if @cost.content == content

    @cost.content = content
    HoneyArt.fit(@cost, @cost_width - 39, 20)
    @cost.x = @cost_x + 34 + (@cost_width - 39 - @cost.width) / 2
    @cost.y = @cost_y + (@cost_height - @cost.height) / 2 - 1
  end

  def set_subtitle(content)
    @subtitle.content = content
  end

  def set_detail(content)
    @detail.content = content if @detail
  end

  def set_level(level)
    @level.content = "NV. #{level}" if @level
  end

  def affordable=(value)
    return if @affordable == value

    @affordable = value
    refresh
  end

  def disabled=(value)
    return if @disabled == value

    @disabled = value
    refresh
  end

  def disabled?
    @disabled
  end

  def active=(value)
    @active = value
    return unless @kind == :tab

    value ? @selected_bg.add : @selected_bg.remove
    @title.color = value ? '#39210c' : '#fff3d2'
    @subtitle.color = value ? '#694019' : '#f8e4c4'
  end

  def hover=(value)
    value &&= !@disabled
    return if @hover == value

    @hover = value
    refresh
  end

  def refresh
    @bg.tint = @hover ? '#fffdf0' : '#ffffff'
    @bg.opacity = @disabled ? 0.82 : 1.0
    if @cost_bg
      @cost_bg.tint = @disabled || !@affordable ? '#d7c6a4' : '#ffffff'
      @cost.color = @disabled || !@affordable ? '#725939' : '#32200c'
    end
    # A warm outline makes hover perceptible without shifting the hit area.
    @title.color = @hover ? '#a75813' : '#24180f' unless @kind == :tab
  end

  def visible=(value)
    return if @visible == value

    @visible = value
    @objects.each { |object| value ? object.add : object.remove }
  end

  def visible?
    @visible
  end
end

class FloatingText
  attr_reader :dead

  def initialize(text, x, y, color = '#fff3cf', size = 22, life = 1.0)
    @shadow = HoneyArt.text(text, x + 1, y + 2, size, '#4c351d', z: 79, bold: true)
    @text = HoneyArt.text(text, x, y, size, color, z: 80, bold: true)
    @life = @max_life = life
    @dead = false
  end

  def update(dt)
    @life -= dt
    [@shadow, @text].each do |object|
      object.y -= 38 * dt
      object.opacity = [@life / @max_life * 2, 0.0, 1.0].sort[1]
      object.remove if @life <= 0
    end
    @dead = @life <= 0
  end
end

class BeeParticle
  attr_reader :dead

  def initialize(x, y, target_x, target_y, speed = 1.0)
    @x, @y, @tx, @ty = x, y, target_x, target_y
    @t, @duration, @dead = 0.0, 3.5 / speed, false
    @arc = rand * Math::PI * 2
    @sprite = HoneyArt.icon('bee', x, y, rand(22..31), 17)
    @sprite.flip = :horizontal if target_x < x
    @trail = 5.times.map { Ruby2D::Circle.new(x: x, y: y, radius: 1.4, color: '#fff9ce', opacity: 0, z: 16) }
  end

  def position_at(t)
    [@x + (@tx - @x) * t, @y + (@ty - @y) * t + Math.sin(t * Math::PI * 4 + @arc) * 18]
  end

  def update(dt, speed)
    @t += dt * speed
    p = [@t / @duration, 1.0].min
    @sprite.x, @sprite.y = position_at(p)
    @sprite.rotate = Math.sin(@t * 15) * 9
    @trail.each_with_index do |dot, index|
      dot.x, dot.y = position_at([p - (index + 1) * 0.025, 0].max)
      dot.x += 9
      dot.y += 13
      dot.opacity = 0.65 - index * 0.1
    end
    return unless p >= 1.0

    [@sprite, *@trail].each(&:remove)
    @dead = true
  end
end
