import random
# define card values
card_values = {
    'Ace': 11,
    '2': 2,
    '3': 3,
    '4': 4,
    '5': 5,
    '6': 6,
    '7': 7,
    '8': 8,
    '9': 9,
    '10': 10,
    'Jack': 10,
    'Queen': 10,
    'King': 10
}

# define hand_value function
def hand_value(cards):
    value = sum(card_values[rank] for suit, rank, color in cards)
    # count the number of aces in the hand
    num_aces = sum(1 for suit, rank, color in cards if rank == 'Ace')
    # handle aces
    while value > 21 and num_aces > 0:
        value -= 10
        num_aces -= 1
    return value
#create a list for dealer and player's cards
dealer_cards=[]
player_cards=[]
#define a function for welcome and introduce the rule of the game
def welcome():
    print("Welcome to play blackjack game!!")
    
#define a add up function

class MoneyChange:
    def __init__(self):
        self.total_money()

    def total_money(self):
        self.total = float(input("Please enter the amount of money you want to bring to the table: "))
        print(f"Your total amount is: {self.total:.2f}$")

    def money_bet(self):
        """
        Prompts the player to enter the amount of money they want to bet for the current play.
        Validates the input to ensure it is a valid number and within the player's total money.
        
        Returns:
        float: The amount of money bet by the player.
        """
        try:
            self.bet = float(input("How much money do you want to bet for this play?"))
        except ValueError:
            print("Invalid input. Please enter a valid number.")
            return self.money_bet()
        while self.bet > self.total or self.bet <= 0 or self.bet != int(self.bet):
            print("Your bet is not valid, please bet again!")
            self.bet = float(input("How much money do you want to bet for this play?"))
            continue 
        print(f"Thank you for your bet! Your bet is: {self.bet:.2f}$! GOOD LUCKY!")
        
        return self.bet

    def win(self):
        self.total += self.bet
        print(f"You won! Now your total is: {self.total:.2f}$")

    def lose(self):
        self.total -= self.bet
        print(f"You lost! Now your total is: {self.total:.2f}$")

    def no_balance(self):
        if self.total <=0:
            print("You don't have enough balance anymore. Please bring more money to the table!")
            return False
        return True


    #initilize the deck cards
    def initialize_deck():
        suits = ['Hearts', 'Diamonds', 'Clubs', 'Spades']
        ranks = ['Ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'Jack', 'Queen', 'King']
        colors = ['Red', 'Black']
        deck = [(suit, rank, color) for suit in suits for rank in ranks for color in colors]*2
        random.shuffle(deck)
        return deck

def dealer_card(deck,dealer_cards):
    dealer_cards=[]
    while len(dealer_cards)!=2:
        dealer_cards.append(deck.pop())
    if len(dealer_cards)==2:
        num1=dealer_cards[0]
        num2=dealer_cards[1]
        print(f'The Dealer has the card showing:{num1}')
        if num1[1]=='Ace' or num2[1]=='Ace':
            print("Dealer is showing an Ace, do you want to buy insurance or not?")
            opt=input("if you want to buy insurance,please press Y if not press N")
            if opt=='Y' or opt=='y':
                print(f"Dealer's under card is {num2}.")
    if hand_value(dealer_cards)==21:
        print("Dealer has 21 and wins! You lost!")
        an.lose()
    elif hand_value(dealer_cards)>21:
        print("Dealer Busted!! You win!!!")
        an.win()

def player_card(deck,player_cards):  
    while len(player_cards)!=2:
        player_cards.append(deck.pop())
    if len(player_cards)==2:
        num1=player_cards[0]
        num2=player_cards[1]
        result=hand_value(player_cards)
        if 'Ace' in (num1[1], num2[1]):
            print('An Ace can be counted as either 1 or 11 points.')
            if result <= 11:
                print(f'Your first card is: {num1}, and your second card is :{num2}. The total could be: {result} or {result+10}')
            else:
                print(f'Your first card is: {num1}, and your second card is :{num2}. The total is: {result}')
        else:
            print(f'Your first card is: {num1}, and your second card is :{num2}. The total is: {result}')




#this get choice function is to get the player's choice to let the player know to hit or stand        
def get_choice(deck,dealer_cards,player_cards,an):
    while hand_value(player_cards) < 21:
        player_choice = input("Do you want to HIT/STAND(H/S)")
        if player_choice == 'H' or player_choice == 'h':
            player_cards.append(deck.pop())
            #there is bug over here to debug later
            print(f'Your got a new card, your card sets are: {player_cards[:]}')
            print(f'You already have {hand_value(player_cards)}. Do you want to Hit/Stand(H/S)')
        else:
            print("You choose to stay!")
            while hand_value(dealer_cards) < 17:
                dealer_cards.append(deck.pop())
                print(f'Dealer now has the cards: {dealer_cards[:]}')
                print(f'Total is: {hand_value(dealer_cards)}')
            else:
                print(f"Dealer has {dealer_cards[:]}, the total dealer has is: {hand_value(dealer_cards)}")
                if hand_value(dealer_cards) > 21:
                    print("Dealer busted! You won!!")
                    an.win()
                elif hand_value(dealer_cards) == 21:
                    print("Dealer has 21. You lost")
                    an.lose()
                break
    if hand_value(player_cards) == 21:
        print("You got 21 already! You won!!")
        an.win()
    elif hand_value(player_cards) > 21:
        print("You busted!! You lost!!")
        an.lose()
    elif hand_value(dealer_cards) < 21:
        print(f"Dealer has total number of: {hand_value(dealer_cards)}")
        if hand_value(dealer_cards) > hand_value(player_cards):
            print(f'Dealer has {hand_value(dealer_cards)}. You have {hand_value(player_cards)}! You lost!!')
            an.lose()
        elif hand_value(dealer_cards) < hand_value(player_cards):
            print(f'Dealer has {hand_value(dealer_cards)}. You have {hand_value(player_cards)}. You win!')
            an.win()

#main function     
if __name__ == "__main__":
    welcome()
    def initialize_deck():
        suits = ['Hearts', 'Diamonds', 'Clubs', 'Spades']
        ranks = ['Ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'Jack', 'Queen', 'King']
        colors = ['Red', 'Black']
        deck = [(suit, rank, color) for suit in suits for rank in ranks for color in colors]*2
        random.shuffle(deck)
        return deck

    an = MoneyChange()
    while True:
        an.money_bet()
        deck = initialize_deck()    
        dealer_cards = []
        player_cards = []
        dealer_card(deck, dealer_cards)
        player_card(deck, player_cards)
        get_choice(deck, dealer_cards, player_cards, an)

        option=input("Do you want to continue this game or not?(Y/N)")
        if option=='Y' or option=='y':
            continue
        else:
            exit()