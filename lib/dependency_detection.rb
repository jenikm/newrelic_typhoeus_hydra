module DependencyDetection
  module_function
  @banned_dependencies = []

  def flag_banned_depdency(dependency)
    @banned_dependencies << dependency
  end

  def banned_dependencies
    @banned_dependencies
  end

  def detect!
    @items.each do |item|
      if item.dependencies_satisfied? && !@banned_dependencies.include?(item.name) 
        item.execute
      end
    end
  end
end

DependencyDetection.flag_banned_depdency :typhoeus
