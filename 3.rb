puts "Digite três números para identificar o maior: "

n1 = gets.to_i
n2 = gets.to_i
n3 = gets.to_i

maior = n1

if n2 > maior
    maior = n2
elsif n3 > maior
    maior = n3
end

puts "O maior número é: #{maior}"