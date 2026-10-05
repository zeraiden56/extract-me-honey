# frozen_string_literal: true

# Counts elapsed seconds, independently of the farm multiplier and frame rate.
# The caller can batch overdue clicks into one visual effect after a slow frame.
class AutoClicker
  def initialize
    reset
  end

  def reset
    @elapsed = 0.0
  end

  def advance(seconds, level)
    if level.zero?
      reset
      return 0
    end

    @elapsed += seconds
    ticks = (@elapsed + 1e-9).floor
    @elapsed = [@elapsed - ticks, 0.0].max
    ticks * level
  end
end
