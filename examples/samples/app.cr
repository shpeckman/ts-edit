# examples/samples/app.cr
module Demo
  class Greeter
    def greet(name : String) : String
      "hello #{name}"
    end

    def shout(name : String) : String
      greet(name).upcase
    end
  end
end
