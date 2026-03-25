-- src/01_enums.lua — Enums, HAND_BASE, DEFAULTS

Sim.ENUMS = {
    SUIT = { SPADES = 1, HEARTS = 2, CLUBS = 3, DIAMONDS = 4 },
    RANK = {
        TWO = 2, THREE = 3, FOUR = 4, FIVE = 5, SIX = 6, SEVEN = 7,
        EIGHT = 8, NINE = 9, TEN = 10, JACK = 11, QUEEN = 12,
        KING = 13, ACE = 14,
    },
    RANK_NOMINAL = {
        [2]=2, [3]=3, [4]=4, [5]=5, [6]=6, [7]=7,
        [8]=8, [9]=9, [10]=10, [11]=10, [12]=10, [13]=10, [14]=11,
    },
    RANK_SYM = {
        [2]="2",[3]="3",[4]="4",[5]="5",[6]="6",[7]="7",
        [8]="8",[9]="9",[10]="10",[11]="J",[12]="Q",[13]="K",[14]="A",
    },
    SUIT_SYM = { [1]="S", [2]="H", [3]="C", [4]="D" },

    HAND_TYPE = {
        FLUSH_FIVE = 1, FLUSH_HOUSE = 2, FIVE_OF_A_KIND = 3,
        STRAIGHT_FLUSH = 4, FOUR_OF_A_KIND = 5, FULL_HOUSE = 6,
        FLUSH = 7, STRAIGHT = 8, THREE_OF_A_KIND = 9,
        TWO_PAIR = 10, PAIR = 11, HIGH_CARD = 12,
    },
    HAND_NAME = {
        [1]="Flush Five",[2]="Flush House",[3]="Five of a Kind",
        [4]="Straight Flush",[5]="Four of a Kind",[6]="Full House",
        [7]="Flush",[8]="Straight",[9]="Three of a Kind",
        [10]="Two Pair",[11]="Pair",[12]="High Card",
    },

    ENHANCEMENT = {
        NONE=0, BONUS=1, MULT=2, WILD=3, GLASS=4,
        STEEL=5, STONE=6, GOLD=7, LUCKY=8,
    },
    EDITION = { NONE=0, FOIL=1, HOLO=2, POLYCHROME=3, NEGATIVE=4 },
    SEAL = { NONE=0, GOLD=1, RED=2, BLUE=3, PURPLE=4 },

    PHASE = {
        SELECTING_HAND = 1, SHOP = 2, PACK_OPEN = 3,
        BLIND_SELECT = 4, GAME_OVER = 5, WIN = 6,
    },

    ACTION = {
        SELECT_CARDS = 1,   -- value = 8-bit bitmask of hand positions
        PLAY_DISCARD = 2,   -- value: 1 = play, 2 = discard
        SHOP_ACTION = 3,    -- value: 0=reroll, 1-5=buy slot, -1~-5=sell joker
        USE_CONSUMABLE = 4, -- value: 1-based consumable index
        PHASE_ACTION = 5,   -- value: 0=end_shop, 1=fight, 2=skip, 3=next, 4=sell cons
        REORDER = 6,        -- value: [src:4][tgt:4][mode:1][area:1]  mode:0=swap 1=insert
    },

    REORDER_AREA = { HAND = 0, JOKER = 1 },

    REWARD = {
        HAND_SCORED  = 0.01,
        BLIND_BEATEN = 10.0,
        ANTE_UP      = 50.0,
        GAME_WON     = 200.0,
        GAME_OVER    = -100.0,
        INVALID      = -0.1,
    },
}

-- Hand base stats {s_mult, s_chips, l_mult, l_chips} from game.lua
Sim.HAND_BASE = {
    [1]={16,160,3,50}, [2]={14,140,4,40}, [3]={12,120,3,35},
    [4]={8,100,4,40},  [5]={7,60,3,30},   [6]={4,40,2,25},
    [7]={4,35,2,15},   [8]={4,30,3,30},   [9]={3,30,2,20},
    [10]={2,20,1,20},  [11]={2,10,1,15},  [12]={1,5,1,10},
}
