import gleam/io
import gleam/string
import gleam/list
import gleam/int
import gleam/order
import gleam/result
import argv

const terminal_character_width: Int = 220

const column_gap_size: Int = 5

type Individual {
  Individual(text: String, display_text: String, score: Int)
}

// This computes the hamming distance
// We could make it better if we scored it based on code point distance, 
// but this works well enough for right now
fn score_text(text: String, target_text: String) -> #(String, Int) {
  case string.first(text), string.first(target_text) {
    Ok(tt_first), Ok(tt_last) -> {
      let #(colored_char, score) = case string.compare(tt_first, tt_last) {
        order.Eq -> #("\u{001b}[38;5;2m" <> tt_first, 1)
        _ -> #("\u{001b}[38;5;9m" <> tt_first, 0)
      }
      let #(colored_rest, score_rest) =
        score_text(string.drop_left(text, 1), string.drop_left(target_text, 1))
      #(colored_char <> colored_rest, score + score_rest)
    }
    _, _ -> #("", 0)
  }
}

fn score_individual(individual: Individual, target_text: String) -> Individual {
  let #(colored_text, score) = score_text(individual.text, target_text)
  Individual(..individual, display_text: colored_text, score: score)
}

fn generate_random_text(length: Int) -> String {
  case length {
    0 -> ""
    _ -> {
      // We can unwrap here as we know this will never be an Error
      int.random(58) + 65
      |> string.utf_codepoint()
      |> result.map(fn(a) { string.from_utf_codepoints([a]) })
      |> result.unwrap("")
      <> generate_random_text(length - 1)
    }
  }
}

fn generate_population_string(
  population: List(Individual),
  columns: Int,
  column_index: Int,
) -> String {
  case population, columns == column_index {
    [first, ..rest], True -> {
      first.display_text <> "\n" <> generate_population_string(rest, columns, 1)
    }
    [first, ..rest], False -> {
      first.display_text
      <> string.repeat(" ", column_gap_size)
      <> generate_population_string(rest, columns, column_index + 1)
    }
    _, _ -> ""
  }
}

fn print_population(population: List(Individual)) {
  // Unwrapping as we know we wont be printing an empty list
  let text =
    population
    |> list.first()
    |> result.map(fn(a) { a.text })
    |> result.unwrap("")
  let columns =
    terminal_character_width / { string.length(text) + column_gap_size }
  io.println(
    string.repeat("\n", 6) <> generate_population_string(population, columns, 1),
  )
}

// I think this function could be written better
fn cross_strings(s1: String, s2: String) {
  case string.first(s1), string.first(s2) {
    Ok(s1_first), Ok(s2_first) -> {
      let char = case int.random(2) {
        0 -> s1_first
        _ -> s2_first
      }
      use rest <- result.try(cross_strings(
        string.drop_left(s1, 1),
        string.drop_left(s2, 1),
      ))
      // 10% chance to randomly add 1, -1, or 0
      case int.random(10) >= 9 {
        True -> {
          use codepoint <- result.try(
            string.to_utf_codepoints(char)
            |> list.first(),
          )
          let int_val = string.utf_codepoint_to_int(codepoint)
          let add = int.random(3) - 1
          use codepoint <- result.try(string.utf_codepoint(int_val + add))
          Ok(string.from_utf_codepoints([codepoint]) <> rest)
        }
        False -> {
          Ok(char <> rest)
        }
      }
    }
    _, _ -> Ok("")
  }
}

fn cross(p1: Individual, p2: Individual) -> Individual {
  let text =
    cross_strings(p1.text, p2.text)
    |> result.unwrap("")
  Individual(text: text, display_text: "", score: 0)
}

fn permute_until_done(
  population: List(Individual),
  target_text: String,
  population_size: Int,
  generation: Int,
) {
  // We want to score and sort our population by score DESC
  let population =
    population
    |> list.map(fn(p) { score_individual(p, target_text) })
    |> list.sort(fn(p1, p2) { int.compare(p2.score, p1.score) })

  print_population(list.take(population, population_size / 2))

  // Check if 50% of the items have solved it
  // If not, perform selection, crossover and mutation, and continue trying
  case
    population
    |> list.take(population_size / 2)
    |> list.all(fn(x) { x.score == string.length(target_text) })
  {
    False -> {
      list.take(population, population_size / 2)
      |> fn(p) { list.zip(p, list.reverse(p)) }
      |> list.map(fn(p) {
        let #(p1, p2) = p
        let p3 = cross(p1, p2)
        let p4 = cross(p1, p2)
        [p1, p2, p3, p4]
      })
      |> list.flatten()
      |> permute_until_done(target_text, population_size, generation + 1)
    }
    True -> {
      print_population(list.take(population, population_size / 2))
    }
  }
}

fn do_work(target_text: String, population_size: Int) {
  list.range(0, population_size)
  |> list.map(fn(_) {
    generate_random_text(string.length(target_text))
    |> Individual("", 0)
  })
  |> permute_until_done(target_text, population_size, 0)
}

pub fn main() {
  case argv.load().arguments {
    ["--text", text, "--population-size", population_size] ->
      do_work(
        text,
        int.parse(population_size)
        |> result.unwrap(1000),
      )
    _ -> do_work("GleamRocks", 1000)
  }
}
