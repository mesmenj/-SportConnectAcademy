import { createTheme } from '@mui/material/styles'

export const colors = { ink:'#163E33', sky:'#D5F279', blue:'#256550', green:'#28B875', orange:'#FF9C45', red:'#E95A62', lilac:'#A789E9', cloud:'#F5F6F2', muted:'#7B857A', line:'#E7EAE3' }

export const theme = createTheme({
  palette: { mode:'light', primary:{main:colors.ink}, secondary:{main:colors.sky}, background:{default:colors.cloud,paper:'#fff'}, success:{main:colors.green}, warning:{main:colors.orange}, error:{main:colors.red} },
  typography: { fontFamily:'Manrope, system-ui, sans-serif', h4:{fontWeight:800,letterSpacing:-1}, h5:{fontWeight:800,letterSpacing:-.6}, h6:{fontWeight:800,letterSpacing:-.3}, subtitle1:{fontWeight:700}, button:{fontWeight:800,textTransform:'none'} },
  shape:{borderRadius:16},
  components:{
    MuiCard:{styleOverrides:{root:{border:`1px solid ${colors.line}`,boxShadow:'0 10px 32px rgba(16,35,63,.06)',borderRadius:22,backgroundImage:'none'}}},
    MuiCardContent:{styleOverrides:{root:{padding:24,'&:last-child':{paddingBottom:24}}}},
    MuiButton:{styleOverrides:{root:{borderRadius:13,boxShadow:'none',minHeight:44,paddingLeft:18,paddingRight:18}}},
    MuiChip:{styleOverrides:{root:{fontWeight:700}}},
    MuiTableCell:{styleOverrides:{root:{paddingTop:16,paddingBottom:16,borderColor:colors.line}}},
    MuiTextField:{defaultProps:{size:'small'}}
  }
})
