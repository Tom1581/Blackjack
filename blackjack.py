import random

# Define card values globally
CARD_VALUES = {
    'Ace': 11, '2': 2, '3': 3, '4': 4, '5': 5,
    '6': 6, '7': 7, '8': 8, '9': 9, '10': 10,
    'Jack': 10, 'Queen': 10, 'King': 10
}

# Define suits and ranks globally
SUITS = ['Hearts', 'Diamonds', 'Clubs', 'Spades']
RANKS = ['Ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'Jack', 'Queen', 'King']

def initialize_deck():
    """Initializes and shuffles a 6-deck shoe."""
    single_deck = [(suit, rank) for suit in SUITS for rank in RANKS]
    # Create a 6-deck shoe by repeating the single deck 6 times
    shoe = single_deck * 6
    random.shuffle(shoe)
    return shoe


def hand_value(cards):
    """Calculates the hand's value and adjusts for aces as needed."""
    value = sum(CARD_VALUES[rank] for _, rank in cards)
    num_aces = sum(rank == 'Ace' for _, rank in cards)
    
    while value > 21 and num_aces:
        value -= 10
        num_aces -= 1
    return value

def cut_deck(deck):
    """Simulates cutting the deck by moving a portion from the top to the bottom."""
    cut_position = random.randint(int(0.25 * len(deck)), int(0.75 * len(deck)))
    return deck[cut_position:] + deck[:cut_position]

class BlackjackGame:
    def __init__(self):
        self.deck = initialize_deck()
        self.player_cards = []
        self.dealer_cards = []
        self.total_money = 1000  # Default starting money
        self.bet = 0
        self.insurance = False
        self.current_count =0
    
    def reset_deck(self):
        """Resets (shuffles and cuts) the deck and resets the count."""
        self.deck = initialize_deck()  # Shuffles a new 6-deck shoe
        self.deck = cut_deck(self.deck)  # Simulates cutting the deck
        self.current_count = 0  # Reset the count
    
    def update_count(self, card):
        """Updates the count based on the card's rank."""
        if card[1] in ['2', '3', '4', '5', '6']:
            self.current_count += 1
        elif card[1] in ['10', 'Jack', 'Queen', 'King', 'Ace']:
            self.current_count -= 1
        # 7, 8, 9 are neutral, so no change to the count

    def deal_initial_cards(self):
        """Deals two cards each to the player and the dealer and updates the count."""
        self.player_cards = [self.deck.pop() for _ in range(2)]
        self.dealer_cards = [self.deck.pop() for _ in range(2)]
        for card in self.player_cards + self.dealer_cards:
            self.update_count(card)
        print(f"Your cards: {self.player_cards}, value: {hand_value(self.player_cards)}")
        print(f"Dealer's showing card: {self.dealer_cards[0]}")
        print(f"Current count: {self.current_count}")

    def place_bet(self):
        """Asks the player for their bet and validates it."""
        try:
            self.bet = float(input("Bet amount: "))
            assert 0 < self.bet <= self.total_money
        except (ValueError, AssertionError):
            print("Invalid bet. Try again.")
            return self.place_bet()

   
    def offer_insurance(self):
        """Offers insurance if the dealer shows an Ace."""
        if self.dealer_cards[0][1] == 'Ace':
            choice = input("Dealer shows an Ace. Do you want to buy insurance? (Y/N): ").lower()
            self.insurance = choice == 'y'
            if self.insurance:
                insurance_bet = self.bet / 2
                self.total_money -= insurance_bet
                print(f"Insurance bet: {insurance_bet}. Total money now: {self.total_money}")

    def check_for_blackjack(self):
        """Checks for initial blackjack."""
        player_value = hand_value(self.player_cards)
        dealer_value = hand_value(self.dealer_cards)

        if player_value == 21 and dealer_value != 21:
            print("Blackjack! You win!")
            self.total_money += self.bet * 1.5
            return True
        elif dealer_value == 21:
            print("Dealer has Blackjack.")
            if self.insurance:
                print("Insurance pays 2:1.")
                self.total_money += self.bet  # Insurance payout
            self.total_money -= self.bet
            return True
        return False

    def player_turn(self):
        """Manages the player's turn, offering the option to hit, stand, or double down."""
        value = hand_value(self.player_cards)
        if value in [9, 10, 11] and len(self.player_cards) == 2:
            action = input("Do you want to hit, stand, or double down? (H/S/D): ").lower()
            if action == 'd':
                self.total_money -= self.bet  # Double the bet
                self.bet *= 2
                print(f"Doubling down. New bet is {self.bet}. Total money now: {self.total_money}")
                new_card = self.deck.pop()
                self.player_cards.append(new_card)
                self.update_count(new_card)
                print(f"Your cards: {self.player_cards}, value: {hand_value(self.player_cards)}")
                return  # End the player's turn after doubling down
        else:
            action = input("Do you want to hit or stand? (H/S): ").lower()

        while action == 'h':
            new_card = self.deck.pop()
            self.player_cards.append(new_card)
            self.update_count(new_card)
            print(f"Your cards: {self.player_cards}, value: {hand_value(self.player_cards)}")
            if hand_value(self.player_cards) >= 21:
                break  # Player must stand if they reach 21 or go bust
            action = input("Do you want to hit or stand? (H/S): ").lower()
    
    def check_for_split(self):
        """Checks if the player's initial two cards are a pair and offers the option to split."""
        if self.player_cards[0][1] == self.player_cards[1][1]:  # Check if the ranks are the same
            action = input("Your cards form a pair. Do you want to split? (Y/N): ").lower()
            if action == 'y':
                self.total_money -= self.bet  # Place an additional bet for the second hand
                # Here, you would need to manage splitting the hands and proceeding with the game
                # This will require additional code to manage multiple hands and adjust gameplay logic accordingly



    def dealer_turn(self):
        """Manages the dealer's turn."""
        while hand_value(self.dealer_cards) < 17:
            new_card = self.deck.pop()
            self.dealer_cards.append(new_card)
            self.update_count(new_card)
            print(f"Dealer's cards: {self.dealer_cards}, value: {hand_value(self.dealer_cards)}")
        print(f"Current count: {self.current_count}")


    def compare_hands(self):
        """Compares the hand values of the player and the dealer to determine the winner."""
        player_value = hand_value(self.player_cards)
        dealer_value = hand_value(self.dealer_cards)

        if player_value > 21 or (dealer_value <= 21 and dealer_value > player_value):
            print("You lose.")
            self.total_money -= self.bet
        elif dealer_value > 21 or player_value > dealer_value:
            print("You win!")
            self.total_money += self.bet
        else:
            print("Push. No one wins.")

    def play_game(self):
        """Runs the game."""
        print("Welcome to Blackjack!")
        while self.total_money > 0:
            print(f"Total money: {self.total_money}")
            self.place_bet()
            self.deal_initial_cards()
            if self.check_for_blackjack():
                continue
            self.offer_insurance()
            self.player_turn()
            if hand_value(self.player_cards) <= 21:
                self.dealer_turn()
            self.compare_hands()
            if input("Continue? (Y/N): ").lower() != 'y':
                break
        print("Thank you for playing.")
    

if __name__ == "__main__":
    game = BlackjackGame()
    
    game.play_game()
