# frozen_string_literal: true

# Run with SDL_VIDEODRIVER=offscreen ruby main.rb --smoke.
# Exercises real event handlers and rendering without reading or writing a save.
class HoneySmoke
  def initialize
    @frame = 0
    @output = File.expand_path('../tmp/smoke', __dir__)
    FileUtils.mkdir_p(@output)
    srand(123)
  end

  def check(condition, message)
    raise "Smoke test: #{message}" unless condition
  end

  def click(x, y)
    window = Ruby2D::DSL.window
    window.mouse_callback(:down, :left, nil, x, y, 0, 0)
    window.mouse_callback(:up, :left, nil, x, y, 0, 0)
  end

  def capture(name)
    Ruby2D::DSL.window.screenshot(File.join(@output, "#{name}.png"))
  end

  def click_perk(context, id)
    button = context.local_variable_get(:perk_buttons).find { |entry| entry.id == id }
    click(button.x + button.width / 2, button.y + button.height / 2)
  end

  def elapse(context, seconds)
    context.local_variable_set(:last_time, Process.clock_gettime(Process::CLOCK_MONOTONIC) - seconds)
  end

  def check_economy_rules(context)
    fresh = context.eval('method(:default_state)')
    sanitize = context.eval('method(:sanitize_state)')
    hps = context.eval('method(:base_hps)')
    reward = context.eval('method(:click_honey)')
    state = fresh.call
    check(reward.call(state) == 1.25, 'initial click must include 25% of passive production')
    %w[hives bee_level queen_level extractor_level cart_level].each do |key|
      upgraded = state.merge(key => state.fetch(key) + 1)
      expected_gain = (hps.call(upgraded) - hps.call(state)) * 0.25
      check((reward.call(upgraded) - reward.call(state) - expected_gain).abs < 1e-8, "#{key} did not scale click rewards with production")
    end

    [13, 100, 10_000].each do |count|
      state['hives'] = count
      restored = sanitize.call(JSON.parse(JSON.generate(state)))
      check(restored['hives'] == count, 'save truncated hives above the old limit')
      check(hps.call(restored) == count, 'hidden hives did not contribute to production')
      [1.0, 8.0, 14.0].each do |speed|
        check(reward.call(restored, speed) >= hps.call(restored) * speed * 0.25, 'click fell behind accelerated passive income')
        check(reward.call(restored, speed) == reward.call(restored) * speed, 'rhythm did not multiply the click')
      end
    end
    [0, -5, 'invalid', nil].each do |count|
      check(sanitize.call('hives' => count)['hives'] == 1, 'invalid hive count must fall back to one')
    end
    check(context.eval('hive_price(100) > hive_price(99)'), 'hive prices stopped growing')
    check(context.eval('format_num(hive_price(10_000))') == '∞', 'large hive prices crashed the shop')

    before = reward.call(state)
    state['gloves_level'] = 1
    check((reward.call(state) - before - (2 + hps.call(state) * 0.05)).abs < 1e-8, 'gloves must improve both flat and passive click rewards')
    state['prestige_count'] = 5
    state['perks'].merge!('golden_frames' => 2, 'steady_hands' => 2)
    permanent = 1.4 * 1.24
    expected = (3 * permanent + hps.call(state) * 0.30) * 1.6 * 8
    check((reward.call(state, 8) - expected).abs < 1e-8, 'permanent click bonuses were lost or applied twice')
  end

  def check_rhythm_rules(context)
    fresh = context.eval('method(:default_state)')
    sanitize = context.eval('method(:sanitize_state)')
    max_speed = context.eval('method(:max_rush_speed)')
    speed = context.eval('method(:rhythm_speed)')
    old_save = fresh.call
    old_save['honey'] = 1234.0
    old_save['perks']['steady_hands'] = 2
    %w[rush_capacity bee_ai].each { |id| old_save['perks'].delete(id) }
    migrated = sanitize.call(old_save)
    check(migrated['honey'] == 1234.0 && migrated['perks']['steady_hands'] == 2, 'save migration lost progress')
    check(migrated['perks'].values_at('rush_capacity', 'bee_ai') == [0, 0], 'old saves must start with the new perks locked')
    check(max_speed.call(migrated) == 8 && speed.call(migrated, 1) == 8, 'base rhythm cap changed')
    migrated['perks'].merge!('rush_capacity' => 3, 'bee_ai' => 2, 'second_wind' => 1)
    restored = sanitize.call(JSON.parse(JSON.generate(migrated)))
    check(restored == migrated, 'new perk levels did not survive a save round trip')
    check(max_speed.call(restored) == 14, 'rhythm cap must grow by 2 per level')
    check(speed.call(restored, 0) == 1 && speed.call(restored, 2) == 14, 'rhythm must stay between 1x and its cap')
    gain = context.eval('method(:rhythm_click_gain)').call(restored)
    decay = context.eval('method(:rhythm_decay)').call(restored)
    check(gain > decay, 'one AbelhIA click per second must sustain rhythm after its prerequisites')

    [10, 30, 60, 144].each do |fps|
      timer = AutoClicker.new
      total = (fps * 10).times.sum { timer.advance(1.0 / fps, 1) }
      check(total == 10, "auto-click cadence depends on FPS (#{fps})")
    end
    timer = AutoClicker.new
    check(timer.advance(100, 0).zero?, 'locked AbelhIA generated clicks')
    check(timer.advance(0.4, 1).zero?, 'unlock retroactively generated clicks')
    check(timer.advance(1.85, 1) == 2 && timer.advance(0.75, 1) == 1, 'slow-frame catch-up lost fractional time')
    check(timer.advance(1, 3) == 3, 'AbelhIA levels did not increase clicks per second')
    timer.advance(0.9, 3)
    timer.reset
    check(timer.advance(0.2, 3).zero?, 'timer reset retained a partial second')
  end

  def step(context)
    @frame += 1
    state = context.local_variable_get(:state)
    case @frame
    when 2
      check_rhythm_rules(context)
      check_economy_rules(context)
      check(state['hives'] == 1, 'fresh game must start with one hive')
      check(state['honey'].positive?, 'passive production stopped')
      capture('new-game')
    when 3
      before = state['honey']
      expected = context.eval('click_honey(state, rush_speed.call)') * 1.5
      click(190, 355)
      check((state['honey'] - before - expected).abs < 1e-8, 'hive click did not grant its scaled bonus')
      check(context.local_variable_get(:rush).positive?, 'field clicks must increase rhythm')
      before = state['hives']
      click(1550, 318)
      check(state['hives'] == before, 'unaffordable purchase was allowed')
      state['honey'] = 1_000_000_000.0
      24.times do
        price = context.eval('hive_price(state.fetch("hives"))')
        before = state['honey']
        click(1550, 318)
        check(state['honey'] == before - price, 'hive purchase charged the wrong price')
      end
      check(state['hives'] == 25, 'hive purchases still stop at the old limit')
      balance = state['honey']
      state['honey'] = 0
      click(1550, 318)
      check(state['hives'] == 25 && state['honey'].zero?, 'unaffordable hive purchase above 12 was allowed')
      state['honey'] = balance
      [[1550, 420], [1550, 520], [1550, 627], [1320, 780], [1550, 780]].each { |x, y| click(x, y) }
      %w[bee queen extractor gloves cart].each do |id|
        check(state["#{id}_level"] == 1, "#{id} purchase failed")
      end
      check(state['honey'] >= 0, 'purchase made honey negative')
      click(1530, 225)
      check(context.local_variable_get(:current_tab) == 'perks', 'legacy tab did not open')
      state['pollen'] = 100
      %w[rush_capacity bee_ai].each do |id|
        click_perk(context, id)
        check(state['perks'][id].zero?, "#{id} bypassed its prerequisite")
      end
      click(1300, 521)
      check(state['perks']['hive_mind'] == 0, 'locked perk was purchasable')
      2.times { click(1300, 395) }
      click(1520, 395)
      2.times { click(1300, 521) }
      2.times { click(1520, 521) }
      click(1300, 661)
      click(1520, 661)
      check(state['perks']['legacy_apiary'] == 1, 'perk tree prerequisites / purchases failed')
      %w[rush_capacity bee_ai].each do |id|
        before = state['pollen']
        price = context.eval('method(:perk_cost)').call(id, 0)
        click_perk(context, id)
        check(state['perks'][id] == 1 && state['pollen'] == before - price, "#{id} purchase failed")
      end
      state['pollen'] = 0
      click_perk(context, 'bee_ai')
      check(state['perks']['bee_ai'] == 1, 'unaffordable AbelhIA upgrade was allowed')
      state['pollen'] = 44
      state['run_honey'] = 250_000.0
    when 5
      context.local_variable_get(:message_bg).remove
      context.local_variable_get(:message_text).content = ''
      capture('legacy')
    when 6
      perks_before = state['perks'].dup
      pollen_before = state['pollen']
      click(1550, 820)
      check(state['prestige_count'] == 1, 'prestige button failed')
      check(state['hives'] == 2, 'inherited hive bonus failed')
      check(state['run_honey'] == 0, 'prestige did not reset run')
      check(state['perks'] == perks_before, 'prestige removed permanent perks')
      check(state['pollen'] == pollen_before + 3, 'prestige pollen reward is wrong')
      click(1300, 225)
      check(context.local_variable_get(:current_tab) == 'shop', 'shop tab did not reopen')
      state.replace(context.eval('default_state'))
      state.merge!('honey' => 2_400_000.0, 'hives' => 37, 'bee_level' => 1,
                   'queen_level' => 15, 'extractor_level' => 13, 'gloves_level' => 4,
                   'cart_level' => 10, 'run_honey' => 2_400_000.0)
      context.local_variable_get(:update_hive_visibility).call
      context.local_variable_set(:rush, 0.79)
      context.local_variable_get(:floating_texts).each { |text| text.update(10) }
      14.times do
        context.local_variable_get(:bees) << BeeParticle.new(rand(70..1080), rand(306..800), rand(70..1080), rand(306..800))
      end
    when 10
      context.local_variable_get(:message_bg).remove
      context.local_variable_get(:message_text).content = ''
      check(!context.local_variable_get(:shop_buttons).first.disabled?, 'hive button disabled above the old limit')
      groups = context.local_variable_get(:hive_sprites)
      check(groups.length == 12, 'unlimited hives created unbounded scenery')
      check(groups.sum { |hive| Integer(hive[:label].content.delete_prefix('x')) } == 37, 'hive group labels lost hives')
      check(context.local_variable_get(:click_text).content == context.eval('format_num(click_honey(state, rush_speed.call))'), 'HUD click reward ignored rhythm')
      before = state['honey']
      expected = context.eval('click_honey(state, rush_speed.call)')
      click(650, 850)
      check((state['honey'] - before - expected).abs < 1e-8, 'field click did not match the displayed reward')
      check(context.local_variable_get(:perk_buttons).none?(&:visible?), 'legacy cards leaked into shop')
      capture('full-apiary')
    when 11
      Ruby2D::DSL.window.set(width: 1000, height: 800)
    when 13
      capture('resized')
    when 15
      %w[new-game legacy full-apiary resized].each do |name|
        check(File.size?(File.join(@output, "#{name}.png")), "missing #{name} screenshot")
      end
      state.replace(context.eval('default_state'))
      state['hives'] = 37
      state['perks'].merge!('steady_hands' => 2, 'second_wind' => 1, 'rush_capacity' => 1, 'bee_ai' => 1)
      state['pollen'] = 100
      context.local_variable_get(:update_hive_visibility).call
      context.local_variable_get(:auto_clicker).reset
      context.local_variable_set(:auto_hive_index, 12)
      context.local_variable_set(:rush, 1.0)
      Ruby2D::DSL.window.set(width: 1280, height: 720)
      elapse(context, 0.2)
    when 16
      check(context.local_variable_get(:auto_clicks).zero?, 'high rhythm accelerated the automatic timer')
      elapse(context, 0.2)
    when 17
      check(context.local_variable_get(:auto_clicks).zero?, 'AbelhIA clicked before one second')
      @before_auto = state['honey']
      elapse(context, 0.65)
    when 18
      check(context.local_variable_get(:auto_clicks) == 1, 'AbelhIA did not click after one second')
      check(context.local_variable_get(:auto_target) == HIVE_POSITIONS.first, 'AbelhIA targeted a nonexistent hive group')
      check(state['honey'] >= @before_auto + context.eval('click_honey(state)') * 1.5, 'automatic hive click missed its honey reward')
      check(context.local_variable_get(:rush) >= 0.98, 'AbelhIA failed to sustain rhythm')
      capture('automation')
      click(1530, 225)
      click_perk(context, 'bee_ai')
      check(state['perks']['bee_ai'] == 2, 'second AbelhIA level could not be purchased')
      context.local_variable_get(:auto_clicker).reset
      elapse(context, 1.05)
    when 19
      check(context.local_variable_get(:auto_clicks) == 2, 'level two did not generate two clicks per second')
      check(context.local_variable_get(:rhythm_status).content == 'AbelhIA: 2 cliques/s', 'automatic status is stale')
      check(context.local_variable_get(:speed_limit_text).content == 'MÁX. x10.0', 'cap indicator is stale')
      capture('new-perks')
    when 20
      context.local_variable_get(:auto_clicker).advance(0.9, 2)
      state['perks']['legacy_apiary'] = MAX_PERK_LEVEL
      state['run_honey'] = 250_000.0
      click(1550, 820)
      check(state['hives'] == 21, 'prestige still caps inherited hives')
      check(state['perks']['bee_ai'] == 2 && state['perks']['rush_capacity'] == 1, 'prestige removed new perks')
      elapse(context, 0.2)
    when 21
      check(context.local_variable_get(:auto_clicks).zero?, 'prestige did not reset the automatic timer')
      elapse(context, 1.05)
    when 22
      check(context.local_variable_get(:auto_clicks) == 2, 'automation stopped after prestige')
      %w[rush_capacity bee_ai].each do |id|
        state['perks'][id] = MAX_PERK_LEVEL
        before = state['pollen'] = 1_000_000_000
        click_perk(context, id)
        check(state['perks'][id] == MAX_PERK_LEVEL && state['pollen'] == before, 'maxed perk charged for an unsavable level')
      end
      puts 'PASS: rendering, unlimited hives, scaled clicks, purchases, tabs, prestige, resize, rhythm cap, automation timing, save migration.'
      puts "Screenshots: #{@output}"
      Ruby2D::DSL.window.close
    end
  end
end
