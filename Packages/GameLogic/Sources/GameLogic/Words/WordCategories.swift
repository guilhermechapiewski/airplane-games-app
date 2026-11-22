/// A themed set of clean, familiar words and short phrases used by Hangman and Word Search.
public struct WordCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// SF Symbol name suggested for this category.
    public let symbol: String
    /// Lowercase entries. May contain spaces, hyphens and apostrophes (phrases).
    public let entries: [String]

    /// Entries made only of letters a–z, between `minLength` and `maxLength` long (for grids).
    public func singleWords(minLength: Int = 3, maxLength: Int = .max) -> [String] {
        entries.filter { word in
            word.count >= minLength && word.count <= maxLength && word.allSatisfy { ("a"..."z").contains($0) }
        }
    }
}

extension WordCategory {
    private static func make(_ id: String, _ title: String, _ symbol: String, _ list: String) -> WordCategory {
        let entries = list.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return WordCategory(id: id, title: title, symbol: symbol, entries: entries)
    }

    /// All built-in categories, hand-written for this project.
    public static let all: [WordCategory] = [
        make("animals", "Animals", "pawprint.fill", """
        alligator, antelope, armadillo, badger, beaver, bison, buffalo, camel, cheetah, chimpanzee,
        chipmunk, cougar, coyote, crocodile, deer, donkey, elephant, ferret, flamingo, fox, gazelle,
        gecko, giraffe, goat, gorilla, hamster, hedgehog, hippo, horse, hyena, iguana, jaguar,
        kangaroo, koala, lemur, leopard, lion, llama, lynx, meerkat, mole, monkey, moose, mouse,
        otter, owl, panda, panther, parrot, peacock, penguin, pig, platypus, porcupine, possum,
        rabbit, raccoon, reindeer, rhino, skunk, sloth, squirrel, tiger, toucan, turtle, walrus,
        weasel, wolf, wombat, yak, zebra, polar bear, guinea pig, sea lion, bald eagle
        """),
        make("food", "Food", "fork.knife", """
        apple, avocado, bagel, banana, biscuit, bread, broccoli, burrito, butter, cabbage, carrot,
        celery, cheese, cherry, chili, cookie, cracker, cupcake, curry, donut, dumpling, garlic,
        grape, honey, lasagna, lemon, lettuce, mango, melon, muffin, mushroom, noodle, oatmeal,
        olive, omelet, onion, orange, pancake, pasta, peach, peanut, pepper, pickle, pizza, popcorn,
        potato, pretzel, pumpkin, quiche, radish, ravioli, salad, salsa, sandwich, sausage, spinach,
        sushi, taco, toast, tomato, tortilla, waffle, yogurt, zucchini, apple pie, hot dog,
        french fries, ice cream, peanut butter, mac and cheese
        """),
        make("countries", "Countries", "globe.americas.fill", """
        argentina, australia, austria, belgium, brazil, canada, chile, china, colombia, croatia,
        cuba, denmark, egypt, ethiopia, finland, france, germany, ghana, greece, iceland, india,
        indonesia, ireland, israel, italy, jamaica, japan, kenya, laos, mexico, mongolia, morocco,
        nepal, netherlands, nigeria, norway, panama, peru, poland, portugal, romania, russia,
        scotland, senegal, singapore, spain, sweden, switzerland, thailand, turkey, uganda,
        ukraine, uruguay, vietnam, wales, zambia, new zealand, south africa, costa rica,
        south korea, sri lanka
        """),
        make("travel", "Travel", "airplane", """
        airport, atlas, backpack, baggage, boarding, border, cabin, camera, compass, cruise,
        customs, departure, ferry, flight, guide, harbor, hostel, hotel, itinerary, journey,
        luggage, map, motel, passport, pilot, postcard, resort, route, safari, souvenir, suitcase,
        taxi, ticket, tour, tourist, train, travel, trip, visa, voyage, window seat, aisle, gate,
        layover, landing, runway, terminal, jet lag, road trip, carry-on, check-in, seat belt,
        snacks, pillow, headphones, adventure, explore, holiday, vacation
        """),
        make("sports", "Sports", "figure.run", """
        archery, badminton, baseball, basketball, bowling, boxing, canoe, cricket, curling, cycling,
        darts, diving, fencing, football, golf, gymnastics, hockey, judo, karate, kayak, lacrosse,
        marathon, polo, rowing, rugby, running, sailing, skating, skiing, soccer, softball, squash,
        surfing, swimming, tennis, triathlon, volleyball, wrestling, yoga, goal, referee, stadium,
        trophy, medal, coach, team, relay, sprint, hurdles, javelin, table tennis, ice skating,
        water polo, high jump, home run, slam dunk
        """),
        make("nature", "Nature", "leaf.fill", """
        acorn, blossom, boulder, branch, brook, canyon, cave, cliff, clover, creek, daisy, desert,
        valley, fern, field, flower, forest, glacier, grass, grove, hill, island, jungle, lake,
        leaf, meadow, moss, mountain, oak, orchid, pebble, petal, pine, pond, prairie, rainbow,
        river, rock, rose, sand, seed, spring, stream, sunflower, swamp, thorn, tree, tulip,
        volcano, waterfall, willow, woods, maple, sprout, root, bark, lily, ivy, pine cone,
        wildflower
        """),
        make("music", "Music", "music.note", """
        accordion, album, alto, bagpipe, ballad, band, banjo, bass, beat, bugle, cello, chord,
        choir, chorus, clarinet, concert, conductor, drum, duet, flute, guitar, harmonica, harp,
        harmony, jazz, lyrics, melody, microphone, opera, orchestra, organ, piano, rhythm, saxophone,
        singer, solo, song, soprano, stage, tambourine, tempo, tenor, trombone, trumpet, tuba,
        tune, ukulele, verse, violin, xylophone, rock and roll, sheet music, encore, record,
        playlist, radio
        """),
        make("space", "Space", "sparkles", """
        alien, asteroid, astronaut, atmosphere, aurora, comet, cosmos, crater, eclipse, galaxy,
        gravity, jupiter, launch, lunar, mars, mercury, meteor, milky way, moon, nebula, neptune,
        orbit, planet, pluto, quasar, rocket, satellite, saturn, shuttle, solar, star, sun,
        supernova, telescope, universe, uranus, venus, earth, black hole, space station, light year,
        big dipper, rover, capsule, module, zero gravity, cosmic, stardust, constellation, nova
        """),
        make("ocean", "Ocean", "water.waves", """
        anchor, beach, coral, crab, current, dolphin, eel, harbor, iceberg, island, jellyfish,
        kelp, lagoon, lighthouse, lobster, manatee, mermaid, octopus, oyster, pearl, pelican,
        penguin, reef, sailboat, salmon, sand, scuba, seagull, seahorse, seal, seaweed, shark,
        shell, shore, shrimp, squid, starfish, submarine, surf, swordfish, tide, tuna, turtle,
        walrus, wave, whale, sea turtle, blue whale, clownfish, sand dollar, high tide, ship,
        sailor, buoy, dock
        """),
        make("jobs", "Jobs", "briefcase.fill", """
        actor, architect, artist, astronaut, author, baker, banker, barber, builder, butcher,
        captain, carpenter, cashier, chef, chemist, coach, dancer, dentist, designer, doctor,
        editor, electrician, engineer, farmer, firefighter, florist, gardener, janitor, judge,
        lawyer, librarian, lifeguard, mechanic, musician, nurse, painter, pharmacist, photographer,
        pilot, plumber, poet, police officer, professor, sailor, scientist, singer, surgeon, tailor,
        teacher, translator, vet, waiter, writer, zookeeper, flight attendant, mail carrier
        """),
        make("household", "Household", "house.fill", """
        armchair, bathtub, bed, blanket, bookcase, broom, bucket, candle, carpet, chair, clock,
        closet, couch, cupboard, curtain, cushion, desk, dishwasher, door, drawer, dresser, faucet,
        fireplace, fork, freezer, kettle, ladder, lamp, laundry, mirror, mop, mug, napkin, oven,
        pillow, plate, quilt, rug, shelf, shower, sink, sofa, spoon, stairs, stove, table, teapot,
        toaster, towel, vacuum, vase, window, doormat, frying pan, light bulb, coffee table,
        alarm clock, washing machine
        """),
        make("weather", "Weather", "cloud.sun.fill", """
        blizzard, breeze, chilly, climate, cloud, cloudy, cold, cyclone, drizzle, drought, flood,
        fog, foggy, forecast, frost, gale, gust, hail, heat, humid, hurricane, ice, lightning,
        mist, monsoon, overcast, rain, rainbow, rainy, sleet, snow, snowflake, sunny, sunshine,
        storm, sunrise, sunset, temperature, thunder, tornado, tropical, typhoon, warm, weather,
        wind, windy, heat wave, cold front, dew, puddle, umbrella, raincoat, thermometer, icicle
        """),
        make("colors", "Colors", "paintpalette.fill", """
        amber, aqua, azure, beige, black, blue, bronze, brown, burgundy, charcoal, coral, cream,
        crimson, cyan, emerald, fuchsia, gold, gray, green, indigo, ivory, jade, khaki, lavender,
        lemon, lilac, lime, magenta, maroon, mauve, mint, navy, ochre, olive, orange, peach, pink,
        plum, purple, red, rose, ruby, rust, salmon, sapphire, scarlet, silver, tan, teal,
        turquoise, violet, white, yellow, sky blue, hot pink, forest green, off-white
        """),
        make("clothing", "Clothing", "tshirt.fill", """
        apron, bandana, belt, beret, bikini, blazer, blouse, boots, bow tie, bracelet, cap, cardigan,
        cloak, coat, collar, dress, earmuffs, gloves, gown, hat, hoodie, jacket, jeans, jersey,
        kilt, leggings, mittens, necklace, overalls, pajamas, parka, poncho, robe, sandals, scarf,
        shirt, shorts, skirt, slippers, sneakers, socks, suit, sweater, swimsuit, tie, tights,
        tuxedo, uniform, vest, wig, raincoat, flip-flops, t-shirt, top hat, sun hat, sweatpants
        """),
        make("science", "Science", "atom", """
        acid, atom, bacteria, beaker, biology, carbon, cell, chemistry, circuit, crystal, data,
        energy, enzyme, experiment, fossil, friction, gene, geology, gravity, helium, hydrogen,
        laboratory, laser, lens, magnet, matter, microscope, mineral, molecule, neutron, nitrogen,
        nucleus, oxygen, particle, physics, plasma, prism, proton, quartz, radiation, research,
        robot, sample, theory, vaccine, volt, electron, magnifying glass, test tube, lab coat,
        periodic table, solar system
        """),
    ]

    /// Looks up a category by its identifier.
    public static func named(_ id: String) -> WordCategory? {
        all.first { $0.id == id }
    }
}
