# list forlder under public/posts
# copy all the sub folder and rename it from - to _
# for example, public/posts/2018/2018-12-28-愛用 => public/posts/2018/2018-12-28_愛用
def main
  Dir.glob("public/posts/*/*") do |f|
    if File.directory?(f)
      # replace "2017-01-01-post-name" => "2017-01-01_post-name"
      new_f = f.gsub(/([0-9]{4}\-[0-9]{2}\-[0-9]{2})\-/) { |match|
        "#{$1}_"
      }
      puts "cp #{f} #{new_f}"
      `cp -r #{f} #{new_f}`
    end
  end
end

main
