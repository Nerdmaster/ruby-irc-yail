# Dynamically adds Array shuffling as described in http://www.ruby-forum.com/topic/163649
class Array
  # Shuffle the array
  def shuffle!
    n = length
    for i in 0...n
      r = Kernel.rand(n-i)+i
      self[r], self[i] = self[i], self[r]
    end
    self
  end

  # Return a shuffled copy of the array
  def shuffle
    dup.shuffle!
  end
end
