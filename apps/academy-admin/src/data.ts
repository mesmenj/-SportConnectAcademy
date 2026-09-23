export type BookingStatus = 'Confirmée' | 'En attente' | 'Terminée' | 'Annulée' | 'Refusée'
export interface Booking { id:string; playerId:string; student:string; initials:string; age:number; coach:string; type:string; date:string; time:string; court:string; location:string; amount:number; currency:string; status:BookingStatus }
export const players = [
  {id:1,name:'Lucas Martin',initials:'LM',age:9,level:'Orange',coach:'David Kengne',academy:'Tennis Club Bonanjo',progress:72,sessions:34,status:'Actif'},
  {id:2,name:'Emma Ngono',initials:'EN',age:11,level:'Vert',coach:'Émilie M.',academy:'Académie Littoral',progress:81,sessions:42,status:'Actif'},
  {id:3,name:'Nathan Etoa',initials:'NE',age:8,level:'Rouge',coach:'David Kengne',academy:'Tennis Club Bonanjo',progress:46,sessions:15,status:'Actif'},
  {id:4,name:'Chloé Mbappe',initials:'CM',age:10,level:'Orange',coach:'Sarah T.',academy:'Club Noah',progress:68,sessions:29,status:'Actif'},
  {id:5,name:'Noah Bell',initials:'NB',age:12,level:'Vert',coach:'Émilie M.',academy:'Académie Littoral',progress:76,sessions:38,status:'En pause'},
  {id:6,name:'Inès Fotso',initials:'IF',age:9,level:'Orange',coach:'David Kengne',academy:'Tennis Club Bonanjo',progress:63,sessions:22,status:'Actif'},
]
export const coaches = [
  {name:'David Kengne',initials:'DK',specialty:'Compétition U8–U12',students:18,sessions:42,rating:4.9,availability:'Disponible'},
  {name:'Émilie M.',initials:'EM',specialty:'Initiation & technique',students:15,sessions:36,rating:4.8,availability:'En séance'},
  {name:'Sarah T.',initials:'ST',specialty:'Préparation physique',students:12,sessions:29,rating:4.9,availability:'Disponible'},
  {name:'Marc Essama',initials:'ME',specialty:'Performance U14',students:16,sessions:34,rating:4.7,availability:'Absent'},
]
export const tournaments = [
  {name:'Little Champions Cup',date:'22–23 août',venue:'Tennis Club Bonanjo',category:'Orange · U10',registered:26,capacity:32,status:'Inscriptions ouvertes'},
  {name:'Douala Junior Open',date:'05–07 sept.',venue:'Club Noah',category:'Vert · U12',registered:38,capacity:48,status:'Inscriptions ouvertes'},
  {name:'Future Stars Series',date:'19 sept.',venue:'Académie Littoral',category:'Orange · U10',registered:24,capacity:24,status:'Complet'},
]
export const revenue = [{day:'Lun',value:168000},{day:'Mar',value:215000},{day:'Mer',value:192000},{day:'Jeu',value:278000},{day:'Ven',value:244000},{day:'Sam',value:356000},{day:'Dim',value:184000}]
export const attendance = [{month:'Mars',value:78},{month:'Avr.',value:81},{month:'Mai',value:79},{month:'Juin',value:86},{month:'Juil.',value:88},{month:'Août',value:91}]
